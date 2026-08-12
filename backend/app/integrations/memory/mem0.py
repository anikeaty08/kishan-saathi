"""Mem0 Platform SDK production adapter."""

import asyncio
from typing import Any
from uuid import UUID

from mem0 import MemoryClient  # type: ignore[import-untyped]

from app.core.errors import ApplicationError
from app.integrations.memory.provider import MemoryFact, MemoryProvider


class Mem0MemoryProvider(MemoryProvider):
    """Wrap the synchronous Mem0 SDK behind an asynchronous scoped contract."""

    def __init__(self, api_key: str, *, client: MemoryClient | None = None) -> None:
        self._client = client or MemoryClient(api_key=api_key)

    async def search_plot(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        query: str,
        limit: int,
    ) -> tuple[MemoryFact, ...]:
        try:
            payload = await asyncio.to_thread(
                self._client.search,
                query,
                user_id=str(farmer_id),
                agent_id=self._agent_id(plot_id),
                limit=limit,
            )
            values: list[dict[str, Any]] = payload.get("results", [])
            return tuple(
                MemoryFact(id=str(item["id"]), text=str(item["memory"]))
                for item in values
                if item.get("id") and item.get("memory")
            )
        except Exception as exc:
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def add_plot_facts(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        facts: tuple[str, ...],
    ) -> None:
        if not facts:
            return
        messages = [{"role": "user", "content": fact} for fact in facts]
        try:
            await asyncio.to_thread(
                self._client.add,
                messages,
                user_id=str(farmer_id),
                agent_id=self._agent_id(plot_id),
                infer=False,
            )
        except Exception as exc:
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def delete_plot_fact(
        self,
        *,
        farmer_id: UUID,
        plot_id: UUID,
        memory_id: str,
    ) -> None:
        del farmer_id, plot_id
        try:
            await asyncio.to_thread(self._client.delete, memory_id)
        except Exception as exc:
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def close(self) -> None:
        return None

    @staticmethod
    def _agent_id(plot_id: UUID) -> str:
        return f"plot:{plot_id}"
