"""Unit tests for the OpenAI Responses progression boundary."""

from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any, cast
from uuid import UUID

import httpx
import openai
import pytest
from openai import AsyncOpenAI
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.progression.openai_responses import (
    PROGRESSION_LANGUAGE_DESCRIPTORS,
    OpenAIProgressionProvider,
)
from app.integrations.progression.provider import (
    ProgressionAnalysis,
    ProgressionImage,
    ProgressionImageQuality,
    ProgressionRequest,
    ProgressionTrend,
)
from app.modules.users.schemas import SupportedLanguage

FARMER = UUID("00000000-0000-0000-0000-000000000001")


class FakeResponses:
    def __init__(self, parsed: ProgressionAnalysis | None) -> None:
        self.parsed = parsed
        self.kwargs: dict[str, Any] = {}

    async def parse(self, **kwargs: Any) -> SimpleNamespace:
        self.kwargs = kwargs
        return SimpleNamespace(id="resp_test", output_parsed=self.parsed)


class FakeClient:
    def __init__(self, parsed: ProgressionAnalysis | None) -> None:
        self.responses = FakeResponses(parsed)


class FailingResponses:
    async def parse(self, **kwargs: Any) -> SimpleNamespace:
        del kwargs
        raise openai.APITimeoutError(request=httpx.Request("POST", "https://api.openai.com"))


class FailingClient:
    def __init__(self) -> None:
        self.responses = FailingResponses()


@pytest.mark.asyncio
async def test_provider_uses_responses_typed_output_and_data_urls() -> None:
    parsed = ProgressionAnalysis(
        trend=ProgressionTrend.IMPROVING,
        confidence=0.78,
        summary="Visible affected area is smaller in the later group.",
        evidence=["Brown area occupies less of the visible leaf surface."],
        limitations=["Lighting differs slightly."],
        image_quality=ProgressionImageQuality(sufficient_for_comparison=True),
    )
    client = FakeClient(parsed)
    provider = OpenAIProgressionProvider(
        Settings(_env_file=None, openai_api_key="test", openai_progression_model="gpt-5"),
        client=cast(AsyncOpenAI, client),
    )

    result = await provider.compare(_request())

    assert result.analysis == parsed
    assert result.model == "gpt-5"
    assert client.responses.kwargs["store"] is False
    assert client.responses.kwargs["text_format"] is ProgressionAnalysis
    assert "Hindi in Devanagari script" in client.responses.kwargs["instructions"]
    content = client.responses.kwargs["input"][0]["content"]
    image_parts = [part for part in content if part["type"] == "input_image"]
    assert len(image_parts) == 2
    assert all(part["image_url"].startswith("data:image/jpeg;base64,") for part in image_parts)


@pytest.mark.asyncio
async def test_provider_rejects_refusal_or_missing_parsed_output() -> None:
    provider = OpenAIProgressionProvider(
        Settings(_env_file=None, openai_api_key="test"),
        client=cast(AsyncOpenAI, FakeClient(None)),
    )

    with pytest.raises(ApplicationError) as raised:
        await provider.compare(_request())

    assert raised.value.code == "PROGRESSION_PROVIDER_INVALID_RESPONSE"


@pytest.mark.asyncio
async def test_provider_maps_timeout_without_leaking_provider_details() -> None:
    provider = OpenAIProgressionProvider(
        Settings(_env_file=None, openai_api_key="test"),
        client=cast(AsyncOpenAI, FailingClient()),
    )

    with pytest.raises(ApplicationError) as raised:
        await provider.compare(_request())

    assert raised.value.code == "PROGRESSION_TEMPORARILY_UNAVAILABLE"
    assert raised.value.status_code == 503


def test_contract_rejects_diagnosis_treatment_and_false_quality_certainty() -> None:
    base = {
        "confidence": 0.5,
        "evidence": ["More brown surface is visible."],
        "limitations": [],
        "image_quality": {"sufficient_for_comparison": True},
    }
    with pytest.raises(ValidationError):
        ProgressionAnalysis.model_validate(
            {**base, "trend": "worsening", "summary": "This diagnoses early blight."}
        )
    with pytest.raises(ValidationError):
        ProgressionAnalysis.model_validate(
            {**base, "trend": "worsening", "summary": "Spray 2 ml per litre."}
        )
    with pytest.raises(ValidationError):
        ProgressionAnalysis.model_validate(
            {
                **base,
                "trend": "improving",
                "summary": "Change is uncertain.",
                "image_quality": {"sufficient_for_comparison": False},
            }
        )


def test_settings_reject_unapproved_progression_model() -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, openai_progression_model="unapproved-model")


def test_every_supported_language_has_a_native_script_descriptor() -> None:
    assert set(PROGRESSION_LANGUAGE_DESCRIPTORS) == {
        language.value for language in SupportedLanguage
    }


def _request() -> ProgressionRequest:
    now = datetime(2026, 8, 13, tzinfo=UTC)
    return ProgressionRequest(
        farmer_id=FARMER,
        earlier_images=(ProgressionImage(UUID(int=10), b"earlier", now),),
        later_images=(ProgressionImage(UUID(int=11), b"later", now),),
        response_language="hi",
    )
