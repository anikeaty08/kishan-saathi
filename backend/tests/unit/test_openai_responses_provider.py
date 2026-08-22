"""Focused orchestration behavior tests for the OpenAI Responses adapter."""

from unittest.mock import AsyncMock

import pytest
from agents import Agent, Runner
from agents.exceptions import ModelBehaviorError

from app.integrations.llm.openai_responses import (
    OpenAIResponsesProvider,
    _complete_words,
    _json_string_field,
    _StreamSafetyViolation,
    _validate_stream_text,
)


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


@pytest.mark.parametrize(
    ("raw", "expected", "complete"),
    [
        ('{"category":"routine"', None, False),
        ('{"short_answer":"Hello far', "Hello far", False),
        ('{"short_answer":"Hello farmer."}', "Hello farmer.", True),
        ('{"short_answer":"Namaste \\u0915\\u093f', "Namaste कि", False),
        ('{"short_answer":"A quoted \\"word\\"."}', 'A quoted "word".', True),
    ],
)
def test_stream_parser_exposes_only_decoded_short_answer(
    raw: str,
    expected: str | None,
    complete: bool,
) -> None:
    assert _json_string_field(raw, "short_answer") == (expected, complete)


def test_partial_stream_holds_the_current_word() -> None:
    assert _complete_words("Hello farm") == "Hello "
    assert _complete_words("Hello farmer ") == "Hello farmer "


def test_stream_safety_allows_routine_guidance() -> None:
    _validate_stream_text(
        "Check the soil and irrigate every 3 days only if it is dry.",
        allow_diagnosis=False,
        allow_specific_treatment=False,
    )


@pytest.mark.parametrize(
    ("text", "allow_diagnosis", "allow_specific_treatment"),
    [
        ("This is early blight.", False, False),
        ("Spray it at 2 g/L.", False, False),
    ],
)
def test_stream_safety_blocks_unsafe_text_before_yield(
    text: str,
    allow_diagnosis: bool,
    allow_specific_treatment: bool,
) -> None:
    with pytest.raises(_StreamSafetyViolation):
        _validate_stream_text(
            text,
            allow_diagnosis=allow_diagnosis,
            allow_specific_treatment=allow_specific_treatment,
        )


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
