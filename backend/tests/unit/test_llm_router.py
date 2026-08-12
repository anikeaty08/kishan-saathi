"""Unit tests for typed model routing policies."""

from uuid import UUID

import pytest

from app.core.config import Settings
from app.integrations.llm.provider import (
    AssistantReply,
    GeneratedTitle,
    LLMProvider,
    LLMRequest,
    LLMResult,
    LLMTask,
    LLMTool,
    MemoryExtraction,
    MemoryExtractionRequest,
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

    async def extract_memories(
        self, request: MemoryExtractionRequest, *, model: str
    ) -> MemoryExtraction:
        del request, model
        return MemoryExtraction()

    async def generate_title(
        self, *, content: str, language: str, farmer_id: UUID, model: str
    ) -> GeneratedTitle:
        del content, language, farmer_id
        self.models.append(model)
        return GeneratedTitle(title="Generated title")


@pytest.mark.asyncio
async def test_router_uses_mini_for_titles_and_primary_for_guidance() -> None:
    provider = RecordingProvider()
    router = LLMRouter(provider, Settings(_env_file=None))
    farmer_id = UUID("00000000-0000-0000-0000-000000000001")

    await router.respond(LLMRequest(LLMTask.TITLE, "test", "test", farmer_id))
    await router.respond(
        LLMRequest(LLMTask.AGRICULTURAL_GUIDANCE, "test", "test", farmer_id)
    )
    title = await router.generate_title(
        content="tomato spots", language="hi", farmer_id=farmer_id
    )

    assert provider.models == ["gpt-5-mini", "gpt-5", "gpt-5-mini"]
    assert title.title == "Generated title"


@pytest.mark.asyncio
async def test_router_preserves_backend_controlled_tools() -> None:
    provider = RecordingProvider()
    captured: list[str] = []

    async def execute() -> str:
        captured.append("called")
        return "forecast"

    tool = LLMTool(
        name="get_plot_weather",
        description="Owned plot only",
        execute=execute,
    )
    request = LLMRequest(
        LLMTask.AGRICULTURAL_GUIDANCE,
        "test",
        "test",
        UUID("00000000-0000-0000-0000-000000000001"),
        tools=(tool,),
    )

    await LLMRouter(provider, Settings(_env_file=None)).respond(request)

    assert request.tools == (tool,)
    assert captured == []
