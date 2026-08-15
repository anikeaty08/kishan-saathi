"""Farmer-controlled memory linking, review, reconciliation, and deletion."""

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import structlog
from sqlalchemy.exc import IntegrityError

from app.core.errors import ApplicationError
from app.integrations.llm.provider import MemoryCandidate, MemoryExtractionRequest
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider, MemoryScope, MemoryScopeType
from app.modules.chats.models import ChatMessage
from app.modules.chats.repository import ChatRepository
from app.modules.farms.repository import FarmRepository
from app.modules.memories.models import ChatMemoryConnection, MemoryCaptureJob, ScopedMemoryFact
from app.modules.memories.repository import MemoryRepository
from app.modules.memories.schemas import (
    ChatMemoryConnectionCreate,
    ChatMemoryConnectionResponse,
    MemoryConnectionTarget,
    MemoryFactResponse,
)


@dataclass(frozen=True, slots=True)
class MemoryCaptureClaim:
    job_id: UUID
    lease_token: UUID


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
        max_capture_attempts: int = 10,
    ) -> None:
        self._repository = repository
        self._chats = chats
        self._farms = farms
        self._provider = provider
        self._llm = llm
        self._max_capture_attempts = max_capture_attempts
        self._logger = structlog.get_logger(__name__)

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
        connection = ChatMemoryConnection(
            farmer_id=farmer_id, chat_id=chat_id, farm_id=farm_id, plot_id=plot_id
        )
        self._repository.add(connection)
        stored = await self._stage_candidates(
            farmer_id,
            chat_id,
            candidates,
            farm_id=farm_id,
            plot_id=plot_id,
        )
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

    def schedule_scoped_message(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        message: ChatMessage,
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
    ) -> MemoryCaptureJob:
        if (farm_id is None) == (plot_id is None):
            raise ApplicationError(code="MEMORY_SCOPE_INVALID", status_code=422)
        job = MemoryCaptureJob(
            farmer_id=farmer_id,
            chat_id=chat_id,
            source_message_id=message.id,
            farm_id=farm_id,
            plot_id=plot_id,
        )
        self._repository.add(job)
        return job

    async def process_capture_jobs(self, claims: list[MemoryCaptureClaim]) -> None:
        """Process owned leases; failures retry and eventually become dead letters."""

        for claim in claims:
            job = await self._repository.get_capture_job(
                claim.job_id,
                lease_token=claim.lease_token,
                for_update=True,
            )
            if job is None:
                continue
            job.lease_expires_at = datetime.now(tz=UTC) + timedelta(minutes=5)
            await self._repository.commit()
            try:
                await self._capture_job(job)
            except Exception as exc:
                await self._repository.rollback()
                job = await self._repository.get_capture_job(
                    claim.job_id,
                    lease_token=claim.lease_token,
                    for_update=True,
                )
                if job is None:
                    continue
                job.attempts += 1
                job.last_error_type = type(exc).__name__
                job.lease_expires_at = None
                job.lease_token = None
                if job.attempts >= self._max_capture_attempts:
                    job.status = "dead"
                    job.dead_at = datetime.now(tz=UTC)
                    self._logger.error(
                        "memory_capture.dead_lettered",
                        job_id=str(job.id),
                        attempts=job.attempts,
                        error_type=job.last_error_type,
                    )
                else:
                    job.status = "pending"
                    job.next_attempt_at = datetime.now(tz=UTC) + timedelta(
                        seconds=min(60 * (2 ** min(job.attempts - 1, 10)), 21600)
                    )
                await self._repository.commit()
            else:
                job = await self._repository.get_capture_job(
                    claim.job_id,
                    lease_token=claim.lease_token,
                    for_update=True,
                )
                if job is None:
                    continue
                await self._repository.delete_capture_job(job)
                await self._repository.commit()

    async def process_due_capture_jobs(self, *, limit: int) -> int:
        now = datetime.now(tz=UTC)
        jobs = await self._repository.due_capture_jobs(now=now, limit=limit)
        claims: list[MemoryCaptureClaim] = []
        if jobs:
            lease_until = now + timedelta(minutes=5)
            for job in jobs:
                token = uuid4()
                job.status = "processing"
                job.next_attempt_at = lease_until
                job.lease_expires_at = lease_until
                job.lease_token = token
                claims.append(MemoryCaptureClaim(job.id, token))
            await self._repository.commit()
        await self.process_capture_jobs(claims)
        return len(claims)

    async def _capture_job(self, job: MemoryCaptureJob) -> None:
        message = await self._chats.message(job.farmer_id, job.chat_id, job.source_message_id)
        if message is None:
            raise ApplicationError(code="MEMORY_SOURCE_MESSAGE_NOT_FOUND", status_code=404)
        farmer_id, chat_id = job.farmer_id, job.chat_id
        farm_id, plot_id = job.farm_id, job.plot_id
        if farm_id is not None:
            farm = await self._farms.get_farm(farmer_id, farm_id)
            if farm is None:
                raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
            scope = MemoryScope(farmer_id, MemoryScopeType.FARM, farm_id)
            target_name = farm.name
        else:
            if plot_id is None:
                raise ApplicationError(code="MEMORY_TARGET_REQUIRED", status_code=422)
            plot = await self._farms.get_plot(farmer_id, plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            scope = MemoryScope(farmer_id, MemoryScopeType.PLOT, plot_id)
            target_name = plot.name
        candidates = await self._extract(farmer_id, [message], scope, target_name)
        stored = await self._stage_candidates(
            farmer_id,
            chat_id,
            candidates,
            farm_id=farm_id,
            plot_id=plot_id,
        )
        try:
            await self._repository.commit()
        except IntegrityError:
            await self._repository.rollback()
            stored = await self._candidate_facts(
                farmer_id,
                candidates,
                farm_id=farm_id,
                plot_id=plot_id,
            )
        for fact in stored:
            await self._repository.refresh(fact)
        if not await self._reconcile(scope, stored):
            raise ApplicationError(code="MEMORY_INDEX_RETRY_PENDING", status_code=503)

    async def _stage_candidates(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        candidates: tuple[MemoryCandidate, ...],
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
    ) -> list[ScopedMemoryFact]:
        normalized_candidates = {self._normalize(candidate.text) for candidate in candidates}
        existing = await self._repository.facts_by_normalized(
            farmer_id,
            farm_id=farm_id,
            plot_id=plot_id,
            normalized=normalized_candidates,
        )
        stored: list[ScopedMemoryFact] = []
        included: set[str] = set()
        for candidate in candidates:
            normalized = self._normalize(candidate.text)
            if normalized in included:
                continue
            included.add(normalized)
            if normalized in existing:
                stored.append(existing[normalized])
                continue
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
            existing[normalized] = fact
            stored.append(fact)
        return stored

    async def _candidate_facts(
        self,
        farmer_id: UUID,
        candidates: tuple[MemoryCandidate, ...],
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
    ) -> list[ScopedMemoryFact]:
        values = await self._repository.facts_by_normalized(
            farmer_id,
            farm_id=farm_id,
            plot_id=plot_id,
            normalized={self._normalize(candidate.text) for candidate in candidates},
        )
        return list(values.values())

    async def list_farm(
        self,
        farmer_id: UUID,
        farm_id: UUID,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[MemoryFactResponse]:
        if await self._farms.get_farm(farmer_id, farm_id) is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        return [
            MemoryFactResponse.model_validate(value)
            for value in await self._repository.list_farm(
                farmer_id, farm_id, limit=limit, offset=offset
            )
        ]

    async def list_plot(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[MemoryFactResponse]:
        if await self._farms.get_plot(farmer_id, plot_id) is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        return [
            MemoryFactResponse.model_validate(value)
            for value in await self._repository.list_plot(
                farmer_id, plot_id, limit=limit, offset=offset
            )
        ]

    async def retry_fact(self, farmer_id: UUID, fact_id: UUID) -> MemoryFactResponse:
        fact = await self._fact(farmer_id, fact_id, for_update=True)
        if fact.index_status not in {"pending", "failed"}:
            raise ApplicationError(code="MEMORY_FACT_NOT_RETRYABLE", status_code=409)
        indexed = await self._reconcile(self._scope(farmer_id, fact.farm_id, fact.plot_id), [fact])
        if not indexed:
            raise ApplicationError(code="MEMORY_INDEX_RETRY_PENDING", status_code=503)
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
        now = datetime.now(tz=UTC)
        if fact.index_status == "indexing":
            raise ApplicationError(code="MEMORY_FACT_INDEX_IN_PROGRESS", status_code=409)
        if fact.index_status == "deleting" and not self._lease_expired(
            fact.operation_lease_expires_at, now
        ):
            raise ApplicationError(code="MEMORY_FACT_DELETE_IN_PROGRESS", status_code=409)
        token = uuid4()
        provider_memory_id = fact.provider_memory_id
        fact.index_status = "deleting"
        fact.operation_lease_token = token
        fact.operation_lease_expires_at = now + timedelta(minutes=5)
        await self._repository.commit()
        if provider_memory_id is not None:
            try:
                await self._provider.delete_fact(memory_id=provider_memory_id)
            except ApplicationError:
                fact = await self._fact(farmer_id, fact_id, for_update=True)
                if fact.operation_lease_token != token:
                    raise ApplicationError(
                        code="MEMORY_FACT_OPERATION_SUPERSEDED", status_code=409
                    ) from None
                fact.index_status = "delete_failed"
                fact.operation_lease_token = None
                fact.operation_lease_expires_at = None
                await self._repository.commit()
                raise
        fact = await self._fact(farmer_id, fact_id, for_update=True)
        if fact.operation_lease_token != token:
            raise ApplicationError(code="MEMORY_FACT_OPERATION_SUPERSEDED", status_code=409)
        await self._repository.delete(fact)
        await self._repository.commit()

    async def _fact(
        self, farmer_id: UUID, fact_id: UUID, *, for_update: bool = False
    ) -> ScopedMemoryFact:
        fact = await self._repository.get_fact(farmer_id, fact_id, for_update=for_update)
        if fact is None:
            raise ApplicationError(code="MEMORY_FACT_NOT_FOUND", status_code=404)
        return fact

    async def _target(
        self, farmer_id: UUID, data: ChatMemoryConnectionCreate
    ) -> tuple[MemoryScope, str, UUID | None, UUID | None]:
        if data.target_type is MemoryConnectionTarget.FARM:
            if data.farm_id is None:
                raise ApplicationError(code="MEMORY_FARM_REQUIRED", status_code=422)
            farm = await self._farms.get_farm(farmer_id, data.farm_id)
            if farm is None:
                raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
            return MemoryScope(farmer_id, MemoryScopeType.FARM, farm.id), farm.name, farm.id, None
        if data.plot_id is None:
            raise ApplicationError(code="MEMORY_PLOT_REQUIRED", status_code=422)
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

    async def _reconcile(self, scope: MemoryScope, facts: list[ScopedMemoryFact]) -> bool:
        all_indexed = True
        for fact in facts:
            locked = await self._repository.get_fact(fact.farmer_id, fact.id, for_update=True)
            if locked is None or locked.index_status == "indexed":
                continue
            now = datetime.now(tz=UTC)
            if locked.index_status == "indexing" and not self._lease_expired(
                locked.operation_lease_expires_at, now
            ):
                all_indexed = False
                await self._repository.rollback()
                continue
            if locked.index_status not in {"pending", "failed", "indexing"}:
                all_indexed = False
                await self._repository.rollback()
                continue
            token = uuid4()
            text = locked.text
            locked.index_status = "indexing"
            locked.operation_lease_token = token
            locked.operation_lease_expires_at = now + timedelta(minutes=5)
            await self._repository.commit()
            try:
                indexed = await self._provider.index_fact(
                    scope=scope, canonical_fact_id=fact.id, text=text
                )
            except ApplicationError:
                locked = await self._repository.get_fact(
                    fact.farmer_id, fact.id, for_update=True
                )
                if locked is None or locked.operation_lease_token != token:
                    all_indexed = False
                    await self._repository.rollback()
                    continue
                locked.index_status = "failed"
                locked.operation_lease_token = None
                locked.operation_lease_expires_at = None
                all_indexed = False
            else:
                locked = await self._repository.get_fact(
                    fact.farmer_id, fact.id, for_update=True
                )
                if locked is None or locked.operation_lease_token != token:
                    all_indexed = False
                    await self._repository.rollback()
                    continue
                locked.provider_memory_id = indexed.id
                locked.index_status = "indexed"
                locked.operation_lease_token = None
                locked.operation_lease_expires_at = None
            try:
                await self._repository.commit()
            except Exception as exc:
                await self._repository.rollback()
                raise ApplicationError(
                    code="MEMORY_INDEX_PERSISTENCE_FAILED", status_code=503
                ) from exc
        return all_indexed

    @staticmethod
    def _lease_expired(value: datetime | None, now: datetime) -> bool:
        if value is None:
            return True
        aware = value if value.tzinfo is not None else value.replace(tzinfo=UTC)
        return aware <= now

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
    def _has_exact_evidence(candidate: MemoryCandidate, user_messages: dict[UUID, str]) -> bool:
        source = user_messages.get(candidate.source_message_id)
        if source is None:
            return False
        quote = " ".join(candidate.evidence_quote.casefold().split())
        fact = " ".join(candidate.text.casefold().split())
        content = " ".join(source.casefold().split())
        return len(quote) >= 4 and quote == fact and quote in content

    @staticmethod
    def _scope(farmer_id: UUID, farm_id: UUID | None, plot_id: UUID | None) -> MemoryScope:
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
