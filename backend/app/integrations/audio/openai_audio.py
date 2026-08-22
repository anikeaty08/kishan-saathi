"""OpenAI Audio API adapter with neutral application failures."""

from collections.abc import AsyncIterator

import openai
from openai import AsyncOpenAI

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.audio.provider import (
    AudioProvider,
    AudioTranscriptionRequest,
    AudioTranscriptionResult,
    SpeechSynthesisRequest,
    SpeechSynthesisResult,
    SpeechSynthesisStream,
)


class OpenAIAudioProvider(AudioProvider):
    """Keep the OpenAI credential and provider-specific API entirely server-side."""

    def __init__(self, settings: Settings, *, client: AsyncOpenAI | None = None) -> None:
        self._client = client or AsyncOpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.openai_audio_timeout_seconds,
            max_retries=1,
        )
        self._transcription_model = settings.openai_transcription_model
        self._speech_model = settings.openai_speech_model
        self._speech_voice = settings.openai_speech_voice

    async def transcribe(self, request: AudioTranscriptionRequest) -> AudioTranscriptionResult:
        try:
            file = (request.filename, request.content, request.content_type)
            if request.language_hint is None:
                response = await self._client.audio.transcriptions.create(
                    model=self._transcription_model,
                    file=file,
                )
            else:
                response = await self._client.audio.transcriptions.create(
                    model=self._transcription_model,
                    file=file,
                    language=request.language_hint,
                )
        except openai.AuthenticationError as exc:
            raise ApplicationError(code="VOICE_AUTHENTICATION_FAILED", status_code=503) from exc
        except (openai.APITimeoutError, openai.APIConnectionError, openai.RateLimitError) as exc:
            raise ApplicationError(code="VOICE_TEMPORARILY_UNAVAILABLE", status_code=503) from exc
        except openai.APIError as exc:
            raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502) from exc

        text = response if isinstance(response, str) else response.text
        normalized = text.strip()
        if not normalized:
            raise ApplicationError(code="VOICE_TRANSCRIPT_EMPTY", status_code=422)
        return AudioTranscriptionResult(text=normalized, model=self._transcription_model)

    async def synthesize(self, request: SpeechSynthesisRequest) -> SpeechSynthesisResult:
        response = None
        try:
            response = await self._client.audio.speech.create(
                model=self._speech_model,
                voice=self._speech_voice,
                input=request.text,
                response_format="mp3",
            )
            content = await response.aread()
        except openai.AuthenticationError as exc:
            raise ApplicationError(code="VOICE_AUTHENTICATION_FAILED", status_code=503) from exc
        except (openai.APITimeoutError, openai.APIConnectionError, openai.RateLimitError) as exc:
            raise ApplicationError(code="VOICE_TEMPORARILY_UNAVAILABLE", status_code=503) from exc
        except openai.APIError as exc:
            raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502) from exc
        finally:
            if response is not None:
                await response.aclose()
        if not content:
            raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)
        return SpeechSynthesisResult(
            content=content,
            media_type="audio/mpeg",
            model=self._speech_model,
            voice=self._speech_voice,
        )

    async def synthesize_stream(self, request: SpeechSynthesisRequest) -> SpeechSynthesisStream:
        async def content() -> AsyncIterator[bytes]:
            try:
                async with self._client.audio.speech.with_streaming_response.create(
                    model=self._speech_model,
                    voice=self._speech_voice,
                    input=request.text,
                    response_format="mp3",
                ) as response:
                    emitted = False
                    async for chunk in response.iter_bytes(chunk_size=64 * 1024):
                        if chunk:
                            emitted = True
                            yield chunk
                    if not emitted:
                        raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)
            except openai.AuthenticationError as exc:
                raise ApplicationError(code="VOICE_AUTHENTICATION_FAILED", status_code=503) from exc
            except (
                openai.APITimeoutError,
                openai.APIConnectionError,
                openai.RateLimitError,
            ) as exc:
                raise ApplicationError(
                    code="VOICE_TEMPORARILY_UNAVAILABLE", status_code=503
                ) from exc
            except openai.APIError as exc:
                raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502) from exc

        return SpeechSynthesisStream(
            content=content(),
            media_type="audio/mpeg",
            model=self._speech_model,
            voice=self._speech_voice,
        )

    async def close(self) -> None:
        await self._client.close()
