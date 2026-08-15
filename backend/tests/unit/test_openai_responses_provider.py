"""Focused orchestration behavior tests for the OpenAI Responses adapter."""

from unittest.mock import AsyncMock

import pytest
from agents import Agent, Runner
from agents.exceptions import ModelBehaviorError

from app.integrations.llm.openai_responses import OpenAIResponsesProvider


@pytest.mark.asyncio
async def test_malformed_structured_output_is_retried_once(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    run = AsyncMock(side_effect=[ModelBehaviorError("invalid JSON"), "valid-result"])
    monkeypatch.setattr(Runner, "run", run)

    result = await OpenAIResponsesProvider._run_with_behavior_retry(
        Agent(name="test", instructions="return a typed result"),
        input_text="untrusted input",
        max_turns=2,
        workflow_name="test workflow",
    )

    assert result == "valid-result"
    assert run.await_count == 2


@pytest.mark.asyncio
async def test_second_malformed_output_is_not_retried_indefinitely(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    run = AsyncMock(side_effect=ModelBehaviorError("invalid JSON"))
    monkeypatch.setattr(Runner, "run", run)

    with pytest.raises(ModelBehaviorError):
        await OpenAIResponsesProvider._run_with_behavior_retry(
            Agent(name="test", instructions="return a typed result"),
            input_text="untrusted input",
            max_turns=2,
            workflow_name="test workflow",
        )

    assert run.await_count == 2
