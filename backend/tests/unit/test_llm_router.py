"""Unit tests for typed model routing policies."""

from uuid import UUID

import pytest

from app.core.config import Settings
from app.integrations.llm.provider import (
    AssistantReply,
    LLMProvider,
    LLMRequest,
    LLMResult,
    LLMTask,
)
from app.integrations.llm.router import LLMRouter


class RecordingProvider(LLMProvider):
    def __init__(self) -> None:
        self.models: list[str] = []

    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        self.models.append(model)
        return LLMResult(AssistantReply(short_answer="ok"), "id", model)

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_router_uses_mini_for_titles_and_primary_for_guidance() -> None:
    provider = RecordingProvider()
    router = LLMRouter(provider, Settings(_env_file=None))
    farmer_id = UUID("00000000-0000-0000-0000-000000000001")

    await router.respond(LLMRequest(LLMTask.TITLE, "test", "test", farmer_id))
    await router.respond(
        LLMRequest(LLMTask.AGRICULTURAL_GUIDANCE, "test", "test", farmer_id)
    )

    assert provider.models == ["gpt-5-mini", "gpt-5"]
