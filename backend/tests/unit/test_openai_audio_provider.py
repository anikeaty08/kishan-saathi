"""Contract tests for the OpenAI audio adapter."""

from types import SimpleNamespace
from typing import Any, cast

import httpx
import openai
import pytest
from openai import AsyncOpenAI

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.audio.openai_audio import OpenAIAudioProvider
from app.integrations.audio.provider import AudioTranscriptionRequest, SpeechSynthesisRequest


class FakeTranscriptions:
    def __init__(self, *, failure: Exception | None = None) -> None:
        self.failure = failure
        self.kwargs: dict[str, Any] = {}

    async def create(self, **kwargs: Any) -> SimpleNamespace:
        self.kwargs = kwargs
        if self.failure is not None:
            raise self.failure
        return SimpleNamespace(text="  मेरे पौधे को क्या हुआ?  ")


class FakeSpeechResponse:
    def __init__(self) -> None:
        self.closed = False

    async def aread(self) -> bytes:
        return b"generated-mp3"

    async def aclose(self) -> None:
        self.closed = True


class FakeSpeech:
    def __init__(self) -> None:
        self.kwargs: dict[str, Any] = {}
        self.response = FakeSpeechResponse()

    async def create(self, **kwargs: Any) -> FakeSpeechResponse:
        self.kwargs = kwargs
        return self.response


class FakeClient:
    def __init__(self, *, failure: Exception | None = None) -> None:
        self.audio = SimpleNamespace(
            transcriptions=FakeTranscriptions(failure=failure),
            speech=FakeSpeech(),
        )
        self.closed = False

    async def close(self) -> None:
        self.closed = True


@pytest.mark.asyncio
async def test_audio_adapter_preserves_script_and_generates_disclosed_mp3() -> None:
    client = FakeClient()
    provider = OpenAIAudioProvider(
        Settings(_env_file=None, openai_api_key="test"),
        client=cast(AsyncOpenAI, client),
    )

    transcript = await provider.transcribe(
        AudioTranscriptionRequest(
            filename="recording.m4a",
            content_type="audio/mp4",
            content=b"audio",
        )
    )
    speech = await provider.synthesize(SpeechSynthesisRequest(text="कल निचली पत्तियों को फिर से देखें।"))

    assert transcript.text == "मेरे पौधे को क्या हुआ?"
    assert client.audio.transcriptions.kwargs["model"] == "gpt-4o-mini-transcribe"
    assert "language" not in client.audio.transcriptions.kwargs
    assert speech.content == b"generated-mp3"
    assert client.audio.speech.kwargs["model"] == "tts-1"
    assert client.audio.speech.kwargs["voice"] == "coral"
    assert client.audio.speech.response.closed is True


@pytest.mark.asyncio
async def test_audio_adapter_normalizes_provider_timeout() -> None:
    failure = openai.APITimeoutError(
        request=httpx.Request("POST", "https://api.openai.com/v1/audio/transcriptions")
    )
    provider = OpenAIAudioProvider(
        Settings(_env_file=None, openai_api_key="test"),
        client=cast(AsyncOpenAI, FakeClient(failure=failure)),
    )

    with pytest.raises(ApplicationError) as raised:
        await provider.transcribe(
            AudioTranscriptionRequest(
                filename="recording.m4a",
                content_type="audio/mp4",
                content=b"audio",
            )
        )

    assert raised.value.code == "VOICE_TEMPORARILY_UNAVAILABLE"
    assert raised.value.status_code == 503
