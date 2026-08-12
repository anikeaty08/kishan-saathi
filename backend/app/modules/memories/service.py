"""Farmer-controlled memory linking, review, reconciliation, and deletion."""

from collections.abc import Iterable
from uuid import UUID

from sqlalchemy.exc import IntegrityError

from app.core.errors import ApplicationError
from app.integrations.llm.provider import MemoryCandidate, MemoryExtractionRequest
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider, MemoryScope, MemoryScopeType
from app.modules.chats.models import ChatMessage
from app.modules.chats.repository import ChatRepository
from app.modules.farms.repository import FarmRepository
from app.modules.memories.models import ChatMemoryConnection, ScopedMemoryFact
from app.modules.memories.repository import MemoryRepository
from app.modules.memories.schemas import (
    ChatMemoryConnectionCreate,
    ChatMemoryConnectionResponse,
    MemoryConnectionTarget,
    MemoryFactResponse,
)


class MemoryService:
    """Keep PostgreSQL canonical and use Mem0 only as a retryable retrieval index."""

    _EXTRACTION_BATCH_MESSAGES = 20

    def __init__(
        self,
        *,
        repository: MemoryRepository,
        chats: ChatRepository,
        farms: FarmRepository,
        provider: MemoryProvider,
        llm: LLMRouter,
    ) -> None:
        self._repository = repository
        self._chats = chats
        self._farms = farms
        self._provider = provider
        self._llm = llm

    async def connect_chat(
        self, farmer_id: UUID, chat_id: UUID, data: ChatMemoryConnectionCreate
    ) -> ChatMemoryConnectionResponse:
        chat = await self._chats.get_chat(farmer_id, chat_id, for_update=True)
        if chat is None:
            raise ApplicationError(code="CHAT_NOT_FOUND", status_code=404)
        if chat.scope_type != "general":
            raise ApplicationError(code="ONLY_GENERAL_CHAT_CAN_BE_CONNECTED", status_code=409)
        existing_connection = await self._repository.get_connection(farmer_id, chat_id)
        if existing_connection is not None:
            return await self._resume_connection(farmer_id, existing_connection)

        scope, target_name, farm_id, plot_id = await self._target(farmer_id, data)
        messages = await self._chats.all_messages(farmer_id, chat_id)
        candidates = await self._extract(farmer_id, messages, scope, target_name)
        existing = await self._repository.existing_normalized(
            farmer_id, farm_id=farm_id, plot_id=plot_id
        )
        connection = ChatMemoryConnection(
            farmer_id=farmer_id, chat_id=chat_id, farm_id=farm_id, plot_id=plot_id
        )
        self._repository.add(connection)
        stored: list[ScopedMemoryFact] = []
        for candidate in candidates:
            normalized = self._normalize(candidate.text)
            if normalized in existing:
                continue
            existing.add(normalized)
            fact = ScopedMemoryFact(
                farmer_id=farmer_id,
                farm_id=farm_id,
                plot_id=plot_id,
                source_chat_id=chat_id,
                source_message_id=candidate.source_message_id,
                evidence_quote=candidate.evidence_quote,
                text=candidate.text,
                normalized_text=normalized,
                index_status="pending",
            )
            self._repository.add(fact)
            stored.append(fact)
        try:
            await self._repository.commit()
        except IntegrityError as exc:
            await self._repository.rollback()
            existing_connection = await self._repository.get_connection(farmer_id, chat_id)
            if existing_connection is None:
                raise ApplicationError(code="MEMORY_CONNECTION_CONFLICT", status_code=409) from exc
            return await self._resume_connection(farmer_id, existing_connection)
        await self._repository.refresh(connection)
        for fact in stored:
            await self._repository.refresh(fact)
        await self._reconcile(scope, stored)
        return await self._connection_response(farmer_id, connection)

    async def list_farm(
        self, farmer_id: UUID, farm_id: UUID
    ) -> list[MemoryFactResponse]:
        if await self._farms.get_farm(farmer_id, farm_id) is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        return [
            MemoryFactResponse.model_validate(value)
            for value in await self._repository.list_farm(farmer_id, farm_id)
        ]

    async def list_plot(
        self, farmer_id: UUID, plot_id: UUID
    ) -> list[MemoryFactResponse]:
        if await self._farms.get_plot(farmer_id, plot_id) is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        return [
            MemoryFactResponse.model_validate(value)
            for value in await self._repository.list_plot(farmer_id, plot_id)
        ]

    async def retry_fact(self, farmer_id: UUID, fact_id: UUID) -> MemoryFactResponse:
        fact = await self._fact(farmer_id, fact_id, for_update=True)
        if fact.index_status not in {"pending", "failed"}:
            raise ApplicationError(code="MEMORY_FACT_NOT_RETRYABLE", status_code=409)
        await self._reconcile(self._scope(farmer_id, fact.farm_id, fact.plot_id), [fact])
        await self._repository.refresh(fact)
        return MemoryFactResponse.model_validate(fact)

    async def disconnect_chat(self, farmer_id: UUID, chat_id: UUID) -> None:
        connection = await self._repository.get_connection(farmer_id, chat_id)
        if connection is None:
            raise ApplicationError(code="MEMORY_CONNECTION_NOT_FOUND", status_code=404)
        if await self._repository.list_connection_facts(farmer_id, chat_id):
            raise ApplicationError(code="MEMORY_CONNECTION_HAS_FACTS", status_code=409)
        await self._repository.delete_connection(connection)
        await self._repository.commit()

    async def delete_fact(self, farmer_id: UUID, fact_id: UUID) -> None:
        fact = await self._fact(farmer_id, fact_id, for_update=True)
        if fact.index_status == "deleting":
            raise ApplicationError(code="MEMORY_FACT_DELETE_IN_PROGRESS", status_code=409)
        fact.index_status = "deleting"
        if fact.provider_memory_id is not None:
            try:
                await self._provider.delete_fact(memory_id=fact.provider_memory_id)
            except ApplicationError:
                fact.index_status = "delete_failed"
                await self._repository.commit()
                raise
        await self._repository.delete(fact)
        await self._repository.commit()

    async def _fact(
        self, farmer_id: UUID, fact_id: UUID, *, for_update: bool = False
    ) -> ScopedMemoryFact:
        fact = await self._repository.get_fact(
            farmer_id, fact_id, for_update=for_update
        )
        if fact is None:
            raise ApplicationError(code="MEMORY_FACT_NOT_FOUND", status_code=404)
        return fact

    async def _target(
        self, farmer_id: UUID, data: ChatMemoryConnectionCreate
    ) -> tuple[MemoryScope, str, UUID | None, UUID | None]:
        if data.target_type is MemoryConnectionTarget.FARM:
            assert data.farm_id is not None
            farm = await self._farms.get_farm(farmer_id, data.farm_id)
            if farm is None:
                raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
            return MemoryScope(farmer_id, MemoryScopeType.FARM, farm.id), farm.name, farm.id, None
        assert data.plot_id is not None
        plot = await self._farms.get_plot(farmer_id, data.plot_id)
        if plot is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        return MemoryScope(farmer_id, MemoryScopeType.PLOT, plot.id), plot.name, None, plot.id

    async def _extract(
        self,
        farmer_id: UUID,
        messages: list[ChatMessage],
        scope: MemoryScope,
        target_name: str,
    ) -> tuple[MemoryCandidate, ...]:
        user_messages = {item.id: item.content for item in messages if item.role == "user"}
        accepted: list[MemoryCandidate] = []
        for batch in self._batches(messages, self._EXTRACTION_BATCH_MESSAGES):
            transcript = "\n".join(
                f"message_id={item.id} role={item.role}: {item.content}" for item in batch
            )
            result = await self._llm.extract_memories(
                MemoryExtractionRequest(
                    transcript=transcript,
                    target_scope=scope.scope_type.value,
                    target_name=target_name,
                    farmer_id=farmer_id,
                )
            )
            accepted.extend(
                candidate
                for candidate in result.facts
                if self._has_exact_evidence(candidate, user_messages)
            )
        return tuple(accepted)

    async def _reconcile(
        self, scope: MemoryScope, facts: list[ScopedMemoryFact]
    ) -> None:
        for fact in facts:
            locked = await self._repository.get_fact(
                fact.farmer_id, fact.id, for_update=True
            )
            if locked is None or locked.index_status not in {"pending", "failed"}:
                continue
            try:
                indexed = await self._provider.index_fact(
                    scope=scope, canonical_fact_id=locked.id, text=locked.text
                )
                locked.provider_memory_id = indexed.id
                locked.index_status = "indexed"
            except ApplicationError:
                locked.index_status = "failed"
            try:
                await self._repository.commit()
            except Exception as exc:
                await self._repository.rollback()
                raise ApplicationError(
                    code="MEMORY_INDEX_PERSISTENCE_FAILED", status_code=503
                ) from exc

    async def _resume_connection(
        self, farmer_id: UUID, connection: ChatMemoryConnection
    ) -> ChatMemoryConnectionResponse:
        facts = await self._repository.list_connection_facts(farmer_id, connection.chat_id)
        pending = [fact for fact in facts if fact.index_status in {"pending", "failed"}]
        if pending:
            await self._reconcile(
                self._scope(farmer_id, connection.farm_id, connection.plot_id), pending
            )
        return await self._connection_response(farmer_id, connection)

    async def _connection_response(
        self, farmer_id: UUID, connection: ChatMemoryConnection
    ) -> ChatMemoryConnectionResponse:
        facts = await self._repository.list_connection_facts(farmer_id, connection.chat_id)
        return ChatMemoryConnectionResponse(
            id=connection.id,
            chat_id=connection.chat_id,
            farm_id=connection.farm_id,
            plot_id=connection.plot_id,
            created_at=connection.created_at,
            memories=[MemoryFactResponse.model_validate(fact) for fact in facts],
        )

    @staticmethod
    def _has_exact_evidence(
        candidate: MemoryCandidate, user_messages: dict[UUID, str]
    ) -> bool:
        source = user_messages.get(candidate.source_message_id)
        if source is None:
            return False
        quote = " ".join(candidate.evidence_quote.casefold().split())
        fact = " ".join(candidate.text.casefold().split())
        content = " ".join(source.casefold().split())
        return len(quote) >= 4 and quote == fact and quote in content

    @staticmethod
    def _scope(
        farmer_id: UUID, farm_id: UUID | None, plot_id: UUID | None
    ) -> MemoryScope:
        if farm_id is not None:
            return MemoryScope(farmer_id, MemoryScopeType.FARM, farm_id)
        if plot_id is not None:
            return MemoryScope(farmer_id, MemoryScopeType.PLOT, plot_id)
        raise RuntimeError("Persisted memory fact has no scope")

    @staticmethod
    def _normalize(text: str) -> str:
        return " ".join(text.casefold().split())[:500]

    @staticmethod
    def _batches(values: list[ChatMessage], size: int) -> Iterable[list[ChatMessage]]:
        for index in range(0, len(values), size):
            yield values[index : index + size]
