"""Integration tests for chat isolation and backend-owned context assembly."""

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.llm.provider import (
    AssistantReply,
    GeneratedTitle,
    LLMProvider,
    LLMRequest,
    LLMResult,
    LLMTask,
    MemoryExtraction,
    MemoryExtractionRequest,
    ReminderProposalDraft,
)
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryFact, MemoryProvider, MemoryScope
from app.integrations.weather.provider import (
    CurrentWeather,
    ForecastDay,
    PlotForecast,
)
from app.modules.chats.repository import ChatRepository
from app.modules.chats.schemas import ChatCreate, ChatMessageCreate, ChatScope, ChatUpdate
from app.modules.chats.service import ChatService
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.models import Crop, Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.memories.repository import MemoryRepository
from app.modules.reminders.repository import ReminderRepository
from app.modules.users.models import FarmerProfile
from app.modules.weather.schemas import CurrentWeatherResponse, PlotForecastResponse
from app.modules.weather.tool import PlotWeatherContext

FARMER = UUID("00000000-0000-0000-0000-000000000001")
OTHER = UUID("00000000-0000-0000-0000-000000000002")


class CapturingLLM(LLMProvider):
    def __init__(self) -> None:
        self.requests: list[tuple[LLMRequest, str]] = []
        self.reply = AssistantReply(short_answer="Check the affected leaves carefully.")

    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        self.requests.append((request, model))
        return LLMResult(
            reply=self.reply,
            provider_response_id="response-1",
            model=model,
        )

    async def close(self) -> None:
        return None

    async def extract_memories(
        self, request: MemoryExtractionRequest, *, model: str
    ) -> MemoryExtraction:
        del request, model
        return MemoryExtraction()

    async def generate_title(
        self, *, content: str, language: str, farmer_id: UUID, model: str
    ) -> GeneratedTitle:
        del content, language, farmer_id
        self.requests.append((LLMRequest(LLMTask.TITLE, "title", "title", FARMER), model))
        return GeneratedTitle(title="Leaf inspection guidance")


class ScopedMemory(MemoryProvider):
    def __init__(self) -> None:
        self.searches: list[tuple[UUID, UUID, str]] = []

    async def search(self, *, scope: MemoryScope, query: str, limit: int) -> tuple[MemoryFact, ...]:
        assert limit == 10
        self.searches.append((scope.farmer_id, scope.scope_id, query))
        return (MemoryFact(id="1", text="Irrigation was completed yesterday"),)

    async def index_fact(
        self, *, scope: MemoryScope, canonical_fact_id: UUID, text: str
    ) -> MemoryFact:
        del scope, canonical_fact_id
        return MemoryFact("1", text)

    async def delete_fact(self, *, memory_id: str) -> None:
        del memory_id

    async def close(self) -> None:
        return None


class StubCurrentWeather:
    name = "stub-current"

    async def current(self, *, latitude: float, longitude: float) -> CurrentWeather:
        del latitude, longitude
        return CurrentWeather(
            observed_at=datetime.now(tz=UTC),
            condition_code=800,
            condition="clear",
            temperature_c=30,
            feels_like_c=31,
            humidity_percent=50,
            wind_speed_mps=2,
        )

    async def close(self) -> None:
        return None


class StubForecastWeather:
    name = "open-meteo"

    async def forecast(self, *, latitude: float, longitude: float) -> PlotForecast:
        del latitude, longitude
        return PlotForecast(
            timezone="Asia/Kolkata",
            generated_at=datetime.now(tz=UTC),
            days=[
                ForecastDay(
                    date=date.today(),
                    condition_code=61,
                    temperature_min_c=22,
                    temperature_max_c=31,
                    precipitation_sum_mm=5,
                    precipitation_probability_max_percent=70,
                    wind_speed_max_kmh=15,
                )
            ],
        )

    async def close(self) -> None:
        return None


class StubPlotWeatherTool:
    async def get(self, farmer_id: UUID, plot_id: UUID) -> PlotWeatherContext:
        del farmer_id, plot_id
        return PlotWeatherContext(
            current=CurrentWeatherResponse(
                weather=await StubCurrentWeather().current(latitude=0, longitude=0),
                provider="openweather",
                fetched_at=datetime.now(tz=UTC),
                is_stale=False,
            ),
            forecast=PlotForecastResponse(
                forecast=await StubForecastWeather().forecast(latitude=0, longitude=0),
                provider="open-meteo",
                fetched_at=datetime.now(tz=UTC),
                is_stale=False,
            ),
        )


@pytest.mark.asyncio
async def test_general_and_plot_chats_use_distinct_context_and_models() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    llm = CapturingLLM()
    memory = ScopedMemory()

    try:
        async with sessions() as session:
            session.add_all([_farmer(FARMER, "a"), _farmer(OTHER, "b")])
            farm = Farm(farmer_id=FARMER, name="Green Farm")
            session.add(farm)
            await session.flush()
            plot = Plot(
                farmer_id=FARMER,
                farm_id=farm.id,
                name="Tomato Plot",
                latitude=20,
                longitude=75,
            )
            session.add(plot)
            await session.flush()
            session.add(Crop(farmer_id=FARMER, plot_id=plot.id, name="Tomato", stage="fruiting"))
            await session.commit()

            service = ChatService(
                repository=ChatRepository(session),
                farms=FarmRepository(session),
                diagnoses=DiagnosisRepository(session),
                memory=memory,
                llm=LLMRouter(llm, Settings(_env_file=None)),
                plot_weather=StubPlotWeatherTool(),
                reminders=ReminderRepository(session),
                canonical_memory=MemoryRepository(session),
            )
            general = await service.create_chat(FARMER, ChatCreate())
            plot_chat = await service.create_chat(
                FARMER,
                ChatCreate(scope_type=ChatScope.PLOT, plot_id=plot.id),
            )
            await service.send_message(
                FARMER,
                general.id,
                ChatMessageCreate(content="How should I inspect leaves?"),
                preferred_language=None,
                idempotency_key="general-message-1",
            )
            plot_reply = await service.send_message(
                FARMER,
                plot_chat.id,
                ChatMessageCreate(content="What should I do next?"),
                preferred_language=None,
                idempotency_key="plot-message-1",
            )
            repeated_plot_reply = await service.send_message(
                FARMER,
                plot_chat.id,
                ChatMessageCreate(content="What should I do next?"),
                preferred_language=None,
                idempotency_key="plot-message-1",
            )
            with pytest.raises(ApplicationError) as hidden:
                await service.get_chat(OTHER, plot_chat.id)
            await service.update_chat(FARMER, plot_chat.id, ChatUpdate(archived=True))
            with pytest.raises(ApplicationError) as archived:
                await service.send_message(
                    FARMER,
                    plot_chat.id,
                    ChatMessageCreate(content="Should fail"),
                    preferred_language=None,
                    idempotency_key="archived-message-1",
                )
            replayed_after_archive = await service.send_message(
                FARMER,
                plot_chat.id,
                ChatMessageCreate(content="What should I do next?"),
                preferred_language=None,
                idempotency_key="plot-message-1",
            )
    finally:
        await engine.dispose()

    guidance_requests = [item for item in llm.requests if item[0].task is not LLMTask.TITLE]
    general_request, general_model = guidance_requests[0]
    plot_request, plot_model = guidance_requests[1]
    assert general_model == "gpt-5"
    assert plot_model == "gpt-5"
    assert "No farm, plot, scan" in general_request.input_text
    assert "Tomato Plot" not in general_request.input_text
    assert "Tomato Plot" in plot_request.input_text
    assert "Irrigation was completed yesterday" not in plot_request.input_text
    assert memory.searches == [(FARMER, plot.id, "What should I do next?")]
    assert general_request.tools == ()
    assert [tool.name for tool in plot_request.tools] == ["get_plot_weather"]
    assert plot_reply.reminder_proposal is None
    assert repeated_plot_reply == plot_reply
    assert replayed_after_archive == plot_reply
    assert len(guidance_requests) == 2
    assert hidden.value.code == "CHAT_NOT_FOUND"
    assert archived.value.code == "CHAT_ARCHIVED"


@pytest.mark.asyncio
async def test_typed_agent_reminder_is_persisted_with_chat_scope() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    llm = CapturingLLM()
    due_at = datetime.now(tz=UTC) + timedelta(days=2)

    llm.reply = AssistantReply(
        short_answer="Inspect again after two days.",
        follow_up_questions=["Did the spots spread?"],
        reminder_proposal=ReminderProposalDraft(title="Inspect leaf spots", due_at=due_at),
    )
    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "a"))
            await session.commit()
            reminders = ReminderRepository(session)
            service = ChatService(
                repository=ChatRepository(session),
                farms=FarmRepository(session),
                diagnoses=DiagnosisRepository(session),
                memory=ScopedMemory(),
                llm=LLMRouter(llm, Settings(_env_file=None)),
                plot_weather=StubPlotWeatherTool(),
                reminders=reminders,
                canonical_memory=MemoryRepository(session),
            )
            chat = await service.create_chat(FARMER, ChatCreate())
            reply = await service.send_message(
                FARMER,
                chat.id,
                ChatMessageCreate(content="Remind me to inspect these spots"),
                preferred_language=None,
                idempotency_key="reminder-message-1",
            )
            assert reply.reminder_proposal is not None
            stored = await reminders.get_proposal(FARMER, reply.reminder_proposal.id)
    finally:
        await engine.dispose()

    assert stored is not None
    assert stored.chat_id == chat.id
    assert stored.status == "pending"
    assert reply.follow_up_questions == ["Did the spots spread?"]


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
