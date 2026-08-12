"""Long-term memory provider contract."""

from dataclasses import dataclass
from typing import Protocol
from uuid import UUID


@dataclass(frozen=True, slots=True)
class MemoryFact:
    id: str
    text: str


class MemoryProvider(Protocol):
    async def search_plot(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        query: str,
        limit: int,
    ) -> tuple[MemoryFact, ...]: ...

    async def add_plot_facts(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        facts: tuple[str, ...],
    ) -> None: ...

    async def delete_plot_fact(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        memory_id: str,
    ) -> None: ...

    async def close(self) -> None: ...


class UnavailableMemoryProvider:
    """Allow chats without long-term memory when Mem0 is unconfigured."""

    async def search_plot(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        query: str,
        limit: int,
    ) -> tuple[MemoryFact, ...]:
        del farmer_id, plot_id, query, limit
        return ()

    async def add_plot_facts(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        facts: tuple[str, ...],
    ) -> None:
        del farmer_id, plot_id, facts

    async def delete_plot_fact(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        memory_id: str,
    ) -> None:
        del farmer_id, plot_id, memory_id

    async def close(self) -> None:
        return None
