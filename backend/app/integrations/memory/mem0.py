"""Mem0 Platform SDK production adapter."""

import asyncio
from typing import Any
from uuid import UUID

from mem0 import MemoryClient  # type: ignore[import-untyped]

from app.core.errors import ApplicationError
from app.integrations.memory.provider import MemoryFact, MemoryProvider, MemoryScope


class Mem0MemoryProvider(MemoryProvider):
    """Use one Mem0 entity plus metadata to isolate farmer workspace memories."""

    def __init__(self, api_key: str, *, client: MemoryClient | None = None) -> None:
        self._api_key = api_key
        self._client: MemoryClient | None = client

    def _sdk(self) -> MemoryClient:
        """Construct lazily so importing the FastAPI app never performs network I/O."""

        if self._client is None:
            self._client = MemoryClient(api_key=self._api_key)
        return self._client

    async def search(
        self, *, scope: MemoryScope, query: str, limit: int
    ) -> tuple[MemoryFact, ...]:
        try:
            payload = await asyncio.to_thread(
                self._sdk().search,
                query,
                filters=self._scope_filters(scope),
                top_k=limit,
            )
            return self._facts(payload)
        except Exception as exc:
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def index_fact(
        self,
        *,
        scope: MemoryScope,
        canonical_fact_id: UUID,
        text: str,
    ) -> MemoryFact:
        """Index idempotently using the canonical PostgreSQL fact ID as metadata."""

        try:
            existing = await asyncio.to_thread(
                self._sdk().get_all,
                filters=self._fact_filters(scope, canonical_fact_id),
                page=1,
                page_size=2,
            )
            facts = self._facts(existing)
            if facts:
                return facts[0]
            payload = await asyncio.to_thread(
                self._sdk().add,
                text,
                user_id=str(scope.farmer_id),
                metadata={
                    "scope_key": self._scope_key(scope),
                    "canonical_fact_id": str(canonical_fact_id),
                },
                infer=False,
                async_mode=False,
            )
            added = self._facts(payload)
            if len(added) != 1:
                raise ValueError("Mem0 did not return exactly one indexed fact")
            return added[0]
        except Exception as exc:
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def delete_fact(self, *, memory_id: str) -> None:
        try:
            await asyncio.to_thread(self._sdk().delete, memory_id=memory_id)
        except Exception as exc:
            if type(exc).__name__ == "MemoryNotFoundError":
                return
            raise ApplicationError(code="MEMORY_PROVIDER_UNAVAILABLE", status_code=503) from exc

    async def close(self) -> None:
        return None

    @classmethod
    def _scope_filters(cls, scope: MemoryScope) -> dict[str, Any]:
        return {
            "AND": [
                {"user_id": str(scope.farmer_id)},
                {"metadata": {"scope_key": cls._scope_key(scope)}},
            ]
        }

    @classmethod
    def _fact_filters(
        cls, scope: MemoryScope, canonical_fact_id: UUID
    ) -> dict[str, Any]:
        return {
            "AND": [
                {"user_id": str(scope.farmer_id)},
                {"metadata": {"scope_key": cls._scope_key(scope)}},
                {"metadata": {"canonical_fact_id": str(canonical_fact_id)}},
            ]
        }

    @staticmethod
    def _scope_key(scope: MemoryScope) -> str:
        return f"{scope.scope_type.value}:{scope.scope_id}"

    @staticmethod
    def _facts(payload: dict[str, Any]) -> tuple[MemoryFact, ...]:
        values: list[dict[str, Any]] = payload.get("results", [])
        return tuple(
            MemoryFact(id=str(item["id"]), text=str(item["memory"]))
            for item in values
            if item.get("id") and item.get("memory")
        )
