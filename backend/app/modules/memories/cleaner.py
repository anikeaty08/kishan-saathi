"""Transactional deletion of long-term facts derived from a scan chat."""

from uuid import UUID

from app.core.errors import ApplicationError
from app.integrations.memory.provider import MemoryProvider
from app.modules.memories.repository import MemoryRepository


class MemoryDiagnosisContextCleaner:
    """Remove remote index entries before canonical scan-context rows are deleted."""

    def __init__(self, repository: MemoryRepository, provider: MemoryProvider) -> None:
        self._repository = repository
        self._provider = provider

    async def delete_scan_context(self, farmer_id: UUID, case_id: UUID) -> None:
        facts = await self._repository.list_diagnosis_facts(
            farmer_id, case_id, for_update=True
        )
        for fact in facts:
            fact.index_status = "deleting"
        if facts:
            await self._repository.commit()
        for fact in facts:
            if fact.provider_memory_id is not None:
                try:
                    await self._provider.delete_fact(memory_id=fact.provider_memory_id)
                except ApplicationError:
                    fact.index_status = "delete_failed"
                    await self._repository.commit()
                    raise
                fact.provider_memory_id = None
                await self._repository.commit()
            await self._repository.delete(fact)
