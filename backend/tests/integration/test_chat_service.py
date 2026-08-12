"""Integration tests for chat isolation and backend-owned context assembly."""

from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.llm.provider import (
    AssistantReply,
    LLMProvider,
    LLMRequest,
    LLMResult,
)
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryFact, MemoryProvider
from app.modules.chats.repository import ChatRepository
from app.modules.chats.schemas import ChatCreate, ChatMessageCreate, ChatScope, ChatUpdate
from app.modules.chats.service import ChatService
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.models import Crop, Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000001")
OTHER = UUID("00000000-0000-0000-0000-000000000002")


class CapturingLLM(LLMProvider):
    def __init__(self) -> None:
        self.requests: list[tuple[LLMRequest, str]] = []

    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        self.requests.append((request, model))
        return LLMResult(
            reply=AssistantReply(
                short_answer="Check the affected leaves carefully.",
                reminder_proposal="Inspect again in two days",
            ),
            provider_response_id="response-1",
            model=model,
        )

    async def close(self) -> None:
        return None


class ScopedMemory(MemoryProvider):
    def __init__(self) -> None:
        self.searches: list[tuple[UUID, UUID, str]] = []

    async def search_plot(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        query: str,
        limit: int,
    ) -> tuple[MemoryFact, ...]:
        assert limit == 5
        self.searches.append((farmer_id, plot_id, query))
        return (MemoryFact(id="1", text="Irrigation was completed yesterday"),)

    async def add_plot_facts(
        self, *, farmer_id: UUID, plot_id: UUID, facts: tuple[str, ...]
    ) -> None:
        del farmer_id, plot_id, facts

    async def delete_plot_fact(
        self, *, farmer_id: UUID, plot_id: UUID, memory_id: str
    ) -> None:
        del farmer_id, plot_id, memory_id

    async def close(self) -> None:
        return None


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
            )
            plot_reply = await service.send_message(
                FARMER,
                plot_chat.id,
                ChatMessageCreate(content="What should I do next?"),
                preferred_language=None,
            )
            with pytest.raises(ApplicationError) as hidden:
                await service.get_chat(OTHER, plot_chat.id)
            await service.update_chat(
                FARMER, plot_chat.id, ChatUpdate(archived=True)
            )
            with pytest.raises(ApplicationError) as archived:
                await service.send_message(
                    FARMER,
                    plot_chat.id,
                    ChatMessageCreate(content="Should fail"),
                    preferred_language=None,
                )
    finally:
        await engine.dispose()

    general_request, general_model = llm.requests[0]
    plot_request, plot_model = llm.requests[1]
    assert general_model == "gpt-5-mini"
    assert plot_model == "gpt-5"
    assert "No farm, plot, scan" in general_request.input_text
    assert "Tomato Plot" not in general_request.input_text
    assert "Tomato Plot" in plot_request.input_text
    assert "Irrigation was completed yesterday" in plot_request.input_text
    assert memory.searches == [(FARMER, plot.id, "What should I do next?")]
    assert plot_reply.reminder_proposal == "Inspect again in two days"
    assert hidden.value.code == "CHAT_NOT_FOUND"
    assert archived.value.code == "CHAT_ARCHIVED"


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
