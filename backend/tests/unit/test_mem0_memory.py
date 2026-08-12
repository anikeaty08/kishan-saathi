"""Mem0 adapter contract tests for entity and metadata isolation."""

from typing import Any
from uuid import UUID

import pytest

from app.integrations.memory.mem0 import Mem0MemoryProvider
from app.integrations.memory.provider import MemoryScope, MemoryScopeType

FARMER = UUID("00000000-0000-0000-0000-000000000081")
PLOT = UUID("00000000-0000-0000-0000-000000000082")
FACT = UUID("00000000-0000-0000-0000-000000000083")


class FakeMem0Client:
    def __init__(self) -> None:
        self.search_kwargs: dict[str, Any] = {}
        self.get_all_kwargs: dict[str, Any] = {}
        self.add_kwargs: dict[str, Any] = {}
        self.deleted: str | None = None
        self.existing: list[dict[str, str]] = []

    def search(self, query: str, **kwargs: Any) -> dict[str, Any]:
        self.search_kwargs = {"query": query, **kwargs}
        return {"results": [{"id": "remote-1", "memory": "Fact"}]}

    def get_all(self, **kwargs: Any) -> dict[str, Any]:
        self.get_all_kwargs = kwargs
        return {"results": self.existing}

    def add(self, messages: object, **kwargs: Any) -> dict[str, Any]:
        self.add_kwargs = {"messages": messages, **kwargs}
        return {"results": [{"id": "remote-1", "memory": str(messages)}]}

    def delete(self, memory_id: str) -> dict[str, str]:
        self.deleted = memory_id
        return {"message": "deleted"}


@pytest.mark.asyncio
async def test_mem0_uses_one_entity_plus_scope_metadata_and_idempotency() -> None:
    client = FakeMem0Client()
    provider = Mem0MemoryProvider("test", client=client)
    scope = MemoryScope(FARMER, MemoryScopeType.PLOT, PLOT)

    result = await provider.search(scope=scope, query="irrigation", limit=5)
    indexed = await provider.index_fact(
        scope=scope, canonical_fact_id=FACT, text="Irrigation completed"
    )
    client.existing = [{"id": "remote-1", "memory": "Irrigation completed"}]
    reused = await provider.index_fact(
        scope=scope, canonical_fact_id=FACT, text="Irrigation completed"
    )
    await provider.delete_fact(memory_id="remote-1")

    assert result[0].id == "remote-1"
    assert indexed.id == reused.id == "remote-1"
    assert client.search_kwargs["filters"] == {
        "AND": [
            {"user_id": str(FARMER)},
            {"metadata": {"scope_key": f"plot:{PLOT}"}},
        ]
    }
    assert "agent_id" not in str(client.search_kwargs)
    assert client.add_kwargs["user_id"] == str(FARMER)
    assert client.add_kwargs["metadata"] == {
        "scope_key": f"plot:{PLOT}",
        "canonical_fact_id": str(FACT),
    }
    assert client.deleted == "remote-1"
