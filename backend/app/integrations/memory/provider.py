"""Long-term memory index contract with explicit owner and workspace scope."""

from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from app.core.errors import ApplicationError


class MemoryScopeType(StrEnum):
    FARM = "farm"
    PLOT = "plot"


@dataclass(frozen=True, slots=True)
class MemoryScope:
    farmer_id: UUID
    scope_type: MemoryScopeType
    scope_id: UUID


@dataclass(frozen=True, slots=True)
class MemoryFact:
    id: str
    text: str


class MemoryProvider(Protocol):
    async def search(
        self, *, scope: MemoryScope, query: str, limit: int
    ) -> tuple[MemoryFact, ...]: ...

    async def index_fact(
        self,
        *,
        scope: MemoryScope,
        canonical_fact_id: UUID,
        text: str,
    ) -> MemoryFact: ...

    async def delete_fact(self, *, memory_id: str) -> None:
        """Delete idempotently; an already-absent provider record is success."""
        ...

    async def close(self) -> None: ...


class UnavailableMemoryProvider:
    """Degrade retrieval, while making requested writes fail honestly."""

    async def search(
        self, *, scope: MemoryScope, query: str, limit: int
    ) -> tuple[MemoryFact, ...]:
        del scope, query, limit
        return ()

    async def index_fact(
        self,
        *,
        scope: MemoryScope,
        canonical_fact_id: UUID,
        text: str,
    ) -> MemoryFact:
        del scope, canonical_fact_id, text
        raise ApplicationError(code="MEMORY_NOT_CONFIGURED", status_code=503)

    async def delete_fact(self, *, memory_id: str) -> None:
        del memory_id
        raise ApplicationError(code="MEMORY_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
