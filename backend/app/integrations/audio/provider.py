"""Typed speech provider contracts."""

from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Protocol

from app.core.errors import ApplicationError


@dataclass(frozen=True, slots=True)
class AudioTranscriptionRequest:
    """One bounded recording that must remain in its original language."""

    filename: str
    content_type: str
    content: bytes
    language_hint: str | None = None


@dataclass(frozen=True, slots=True)
class AudioTranscriptionResult:
    text: str
    model: str


@dataclass(frozen=True, slots=True)
class SpeechSynthesisRequest:
    """Validated assistant text selected from an owned chat message."""

    text: str


@dataclass(frozen=True, slots=True)
class SpeechSynthesisResult:
    content: bytes
    media_type: str
    model: str
    voice: str


@dataclass(frozen=True, slots=True)
class SpeechSynthesisStream:
    content: AsyncIterator[bytes]
    media_type: str
    model: str
    voice: str


class AudioProvider(Protocol):
    async def transcribe(self, request: AudioTranscriptionRequest) -> AudioTranscriptionResult: ...

    async def synthesize(self, request: SpeechSynthesisRequest) -> SpeechSynthesisResult: ...

    async def synthesize_stream(self, request: SpeechSynthesisRequest) -> SpeechSynthesisStream: ...

    async def close(self) -> None: ...


class UnavailableAudioProvider:
    async def transcribe(self, request: AudioTranscriptionRequest) -> AudioTranscriptionResult:
        del request
        raise ApplicationError(code="VOICE_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def synthesize(self, request: SpeechSynthesisRequest) -> SpeechSynthesisResult:
        del request
        raise ApplicationError(code="VOICE_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def synthesize_stream(self, request: SpeechSynthesisRequest) -> SpeechSynthesisStream:
        del request
        raise ApplicationError(code="VOICE_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
