"""Integration tests for chat isolation and backend-owned context assembly."""

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.llm.provider import (
    AssistantReply,
    ChatRiskClassification,
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
from app.modules.chats.models import ChatMessage
from app.modules.chats.repository import ChatRepository
from app.modules.chats.schemas import ChatCreate, ChatMessageCreate, ChatScope, ChatUpdate
from app.modules.chats.service import ChatService
from app.modules.diagnoses.models import DiagnosisAssessment, DiagnosisCase
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.models import Crop, Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.memories.models import ChatMemoryConnection, MemoryCaptureJob
from app.modules.memories.repository import MemoryRepository
from app.modules.memories.writer import ScopedMemoryWriter
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

    async def classify_chat_risk(
        self, *, content: str, farmer_id: UUID, model: str
    ) -> ChatRiskClassification:
        del farmer_id
        self.requests.append((LLMRequest(LLMTask.ROUTING, "route", content, FARMER), model))
        return ChatRiskClassification(
            requires_primary_model=(
                '"has_plot_context": true' in content.casefold() or "next" in content.casefold()
            ),
            reason_code="test",
        )


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


class RecordingMemoryWriter(ScopedMemoryWriter):
    def __init__(self) -> None:
        self.captures: list[tuple[UUID, UUID, UUID | None, UUID | None, str]] = []

    def schedule_scoped_message(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        message: ChatMessage,
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
    ) -> MemoryCaptureJob:
        self.captures.append((farmer_id, chat_id, farm_id, plot_id, message.content))
        return MemoryCaptureJob(
            farmer_id=farmer_id,
            chat_id=chat_id,
            source_message_id=message.id,
            farm_id=farm_id,
            plot_id=plot_id,
        )


@pytest.mark.asyncio
async def test_general_and_plot_chats_use_distinct_context_and_models() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    llm = CapturingLLM()
    memory = ScopedMemory()
    memory_writer = RecordingMemoryWriter()

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
            crop = Crop(farmer_id=FARMER, plot_id=plot.id, name="Tomato", stage="fruiting")
            diagnosis_case = DiagnosisCase(
                farmer_id=FARMER,
                farm_id=farm.id,
                plot_id=plot.id,
                plant_name="Tomato",
                title="Tomato leaf diagnosis",
                status="completed",
            )
            session.add_all([crop, diagnosis_case])
            await session.flush()
            session.add(
                DiagnosisAssessment(
                    farmer_id=FARMER,
                    case_id=diagnosis_case.id,
                    predicted_crop="tomato",
                    primary_disease="tomato early blight",
                    confidence=0.81,
                    confidence_label="high",
                    model_name="test-ensemble",
                    model_version="1",
                    is_active=True,
                )
            )
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
                memory_writer=memory_writer,
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

    guidance_requests = [
        item for item in llm.requests if item[0].task not in {LLMTask.TITLE, LLMTask.ROUTING}
    ]
    general_request, general_model = guidance_requests[0]
    plot_request, plot_model = guidance_requests[1]
    assert general_model == "gpt-5-mini"
    assert plot_model == "gpt-5"
    assert "No farm, plot, scan" in general_request.input_text
    assert "Tomato Plot" not in general_request.input_text
    assert "Tomato Plot" in plot_request.input_text
    assert "Recent plot diagnosis: tomato / tomato early blight" in plot_request.input_text
    assert "Current and forecast plot weather" in plot_request.input_text
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
    assert memory_writer.captures == [
        (FARMER, plot_chat.id, None, plot.id, "What should I do next?")
    ]


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
                memory_writer=RecordingMemoryWriter(),
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


@pytest.mark.asyncio
async def test_chat_detail_and_message_pages_are_bounded() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "bounded"))
            await session.commit()
            service = _chat_service(session)
            chat = await service.create_chat(FARMER, ChatCreate())
            session.add_all(
                [
                    ChatMessage(
                        farmer_id=FARMER,
                        chat_id=chat.id,
                        sequence=sequence,
                        role="user" if sequence % 2 else "assistant",
                        content=f"message-{sequence}",
                    )
                    for sequence in range(1, 61)
                ]
            )
            await session.commit()

            detail = await service.get_chat(FARMER, chat.id)
            newest_page = await service.message_page(
                FARMER, chat.id, limit=20, before_sequence=None
            )
            older_page = await service.message_page(
                FARMER,
                chat.id,
                limit=20,
                before_sequence=newest_page.next_before_sequence,
            )
    finally:
        await engine.dispose()

    assert [item.sequence for item in detail.messages] == list(range(11, 61))
    assert [item.sequence for item in newest_page.items] == list(range(41, 61))
    assert newest_page.next_before_sequence == 41
    assert [item.sequence for item in older_page.items] == list(range(21, 41))
    assert older_page.next_before_sequence == 21


@pytest.mark.asyncio
async def test_chat_filters_resolve_connections_and_current_diagnosis_scope() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "scope"))
            old_farm = Farm(farmer_id=FARMER, name="Old Farm")
            new_farm = Farm(farmer_id=FARMER, name="New Farm")
            session.add_all([old_farm, new_farm])
            await session.flush()
            old_plot = Plot(
                farmer_id=FARMER,
                farm_id=old_farm.id,
                name="Old Plot",
                latitude=20,
                longitude=75,
            )
            new_plot = Plot(
                farmer_id=FARMER,
                farm_id=new_farm.id,
                name="New Plot",
                latitude=21,
                longitude=76,
            )
            session.add_all([old_plot, new_plot])
            await session.flush()
            diagnosis = DiagnosisCase(
                farmer_id=FARMER,
                farm_id=old_farm.id,
                plot_id=old_plot.id,
                title="Leaf case",
                status="completed",
            )
            session.add(diagnosis)
            await session.commit()

            service = _chat_service(session)
            general = await service.create_chat(FARMER, ChatCreate())
            scan = await service.create_chat(
                FARMER,
                ChatCreate(scope_type=ChatScope.SCAN, diagnosis_case_id=diagnosis.id),
            )
            session.add(
                ChatMemoryConnection(
                    farmer_id=FARMER,
                    chat_id=general.id,
                    plot_id=new_plot.id,
                )
            )
            diagnosis.farm_id = new_farm.id
            diagnosis.plot_id = new_plot.id
            await session.commit()

            new_plot_chats = await service.list_chats(
                FARMER,
                include_archived=False,
                plot_id=new_plot.id,
            )
            new_farm_chats = await service.list_chats(
                FARMER,
                include_archived=False,
                farm_id=new_farm.id,
            )
            old_plot_chats = await service.list_chats(
                FARMER,
                include_archived=False,
                plot_id=old_plot.id,
            )
    finally:
        await engine.dispose()

    assert {item.id for item in new_plot_chats} == {general.id, scan.id}
    assert {item.id for item in new_farm_chats} == {general.id, scan.id}
    assert old_plot_chats == []


def _chat_service(session: AsyncSession) -> ChatService:
    return ChatService(
        repository=ChatRepository(session),
        farms=FarmRepository(session),
        diagnoses=DiagnosisRepository(session),
        memory=ScopedMemory(),
        llm=LLMRouter(CapturingLLM(), Settings(_env_file=None)),
        plot_weather=StubPlotWeatherTool(),
        reminders=ReminderRepository(session),
        canonical_memory=MemoryRepository(session),
        memory_writer=RecordingMemoryWriter(),
    )


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
