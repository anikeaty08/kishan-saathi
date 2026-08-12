"""Integration tests for filtered, farmer-controlled scoped memory."""

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
    MemoryCandidate,
    MemoryExtraction,
    MemoryExtractionRequest,
)
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryFact, MemoryProvider, MemoryScope
from app.modules.chats.models import ChatMessage, ChatSession
from app.modules.chats.repository import ChatRepository
from app.modules.farms.models import Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.memories.repository import MemoryRepository
from app.modules.memories.schemas import (
    ChatMemoryConnectionCreate,
    MemoryConnectionTarget,
)
from app.modules.memories.service import MemoryService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000061")
OTHER = UUID("00000000-0000-0000-0000-000000000062")


class ExtractingLLM(LLMProvider):
    def __init__(self) -> None:
        self.requests: list[tuple[MemoryExtractionRequest, str]] = []

    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        del request
        return LLMResult(AssistantReply(short_answer="ok"), "id", model)

    async def extract_memories(
        self, request: MemoryExtractionRequest, *, model: str
    ) -> MemoryExtraction:
        self.requests.append((request, model))
        first_line = next(
            line for line in request.transcript.splitlines() if "role=user:" in line
        )
        message_id = UUID(first_line.split()[0].split("=", 1)[1])
        return MemoryExtraction(
            facts=[
                MemoryCandidate(
                    text="I planted tomato in June",
                    source_message_id=message_id,
                    evidence_quote="I planted tomato in June",
                ),
                MemoryCandidate(
                    text="  i   planted TOMATO in June  ",
                    source_message_id=message_id,
                    evidence_quote="I planted tomato in June",
                ),
            ]
        )

    async def close(self) -> None:
        return None

    async def generate_title(
        self, *, content: str, language: str, farmer_id: UUID, model: str
    ) -> GeneratedTitle:
        del content, language, farmer_id, model
        return GeneratedTitle(title="Memory chat")


class RecordingMemory(MemoryProvider):
    def __init__(self) -> None:
        self.adds: list[tuple[MemoryScope, tuple[str, ...]]] = []
        self.deletes: list[tuple[MemoryScope, str]] = []

    async def search(
        self, *, scope: MemoryScope, query: str, limit: int
    ) -> tuple[MemoryFact, ...]:
        del scope, query, limit
        return ()

    async def list(self, *, scope: MemoryScope, limit: int) -> tuple[MemoryFact, ...]:
        del scope, limit
        return ()

    async def index_fact(
        self, *, scope: MemoryScope, canonical_fact_id: UUID, text: str
    ) -> MemoryFact:
        del canonical_fact_id
        self.adds.append((scope, (text,)))
        return MemoryFact("remote-0", text)

    async def delete_fact(self, *, memory_id: str) -> None:
        self.deletes.append((self.adds[0][0], memory_id))

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_general_chat_is_filtered_deduplicated_and_connected_once() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    llm = ExtractingLLM()
    provider = RecordingMemory()

    try:
        async with sessions() as session:
            session.add_all([_farmer(FARMER, "owner"), _farmer(OTHER, "other")])
            farm = Farm(farmer_id=FARMER, name="Home Farm")
            session.add(farm)
            await session.flush()
            plot = Plot(
                farmer_id=FARMER,
                farm_id=farm.id,
                name="Tomato Plot",
                latitude=18,
                longitude=74,
            )
            chat = ChatSession(farmer_id=FARMER, scope_type="general")
            session.add_all([plot, chat])
            await session.flush()
            session.add_all(
                [
                    ChatMessage(
                        farmer_id=FARMER,
                        chat_id=chat.id,
                        sequence=1,
                        role="user",
                        content="I planted tomato in June. What should I do?",
                    ),
                    ChatMessage(
                        farmer_id=FARMER,
                        chat_id=chat.id,
                        sequence=2,
                        role="assistant",
                        content="You could inspect it tomorrow.",
                    ),
                ]
            )
            await session.commit()
            service = MemoryService(
                repository=MemoryRepository(session),
                chats=ChatRepository(session),
                farms=FarmRepository(session),
                provider=provider,
                llm=LLMRouter(llm, Settings(_env_file=None)),
            )

            connected = await service.connect_chat(
                FARMER,
                chat.id,
                ChatMemoryConnectionCreate(
                    target_type=MemoryConnectionTarget.PLOT,
                    plot_id=plot.id,
                ),
            )
            repeated = await service.connect_chat(
                FARMER,
                chat.id,
                ChatMemoryConnectionCreate(
                    target_type=MemoryConnectionTarget.FARM,
                    farm_id=farm.id,
                ),
            )
            with pytest.raises(ApplicationError) as hidden:
                await service.list_plot(OTHER, plot.id)
            with pytest.raises(ApplicationError) as not_retryable:
                await service.retry_fact(FARMER, connected.memories[0].id)
            await service.delete_fact(FARMER, connected.memories[0].id)
    finally:
        await engine.dispose()

    assert len(connected.memories) == 1
    assert connected.memories[0].index_status == "indexed"
    assert llm.requests[0][1] == "gpt-5-mini"
    assert "assistant: You could inspect it tomorrow." in llm.requests[0][0].transcript
    assert provider.adds[0][0].scope_id == plot.id
    assert provider.adds[0][1] == ("I planted tomato in June",)
    assert provider.deletes[0][0].scope_id == plot.id
    assert provider.deletes[0][1] == "remote-0"
    assert repeated.id == connected.id
    assert repeated.plot_id == plot.id
    assert hidden.value.code == "PLOT_NOT_FOUND"
    assert not_retryable.value.code == "MEMORY_FACT_NOT_RETRYABLE"


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
