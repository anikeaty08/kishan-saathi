"""Owner-scoped transcription and assistant speech orchestration."""

from collections.abc import AsyncIterator
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.audio.provider import (
    AudioProvider,
    AudioTranscriptionRequest,
    SpeechSynthesisRequest,
    SpeechSynthesisResult,
    SpeechSynthesisStream,
)
from app.modules.chats.repository import ChatRepository
from app.modules.voice.schemas import VoiceTranscriptionResponse


@dataclass(frozen=True, slots=True)
class IncomingAudio:
    filename: str
    content_type: str
    content: bytes


class VoiceService:
    """Voice is only an I/O layer; it never creates a chat message itself."""

    _PROVIDER_SPEECH_CHUNK_CHARACTERS = 3800

    _SUPPORTED_TRANSCRIPTION_SUFFIXES = {
        ".m4a",
        ".mp3",
        ".mp4",
        ".mpeg",
        ".mpga",
        ".wav",
        ".webm",
    }

    @staticmethod
    def _matches_audio_container(suffix: str, content: bytes) -> bool:
        """Reject renamed arbitrary uploads before sending them to the paid provider."""

        if suffix in {".m4a", ".mp4"}:
            return len(content) >= 12 and content[4:8] == b"ftyp"
        if suffix in {".mp3", ".mpeg", ".mpga"}:
            return content.startswith(b"ID3") or (
                len(content) >= 2 and content[0] == 0xFF and content[1] & 0xE0 == 0xE0
            )
        if suffix == ".wav":
            return len(content) >= 12 and content.startswith(b"RIFF") and content[8:12] == b"WAVE"
        if suffix == ".webm":
            return content.startswith(b"\x1aE\xdf\xa3")
        return False

    def __init__(
        self,
        *,
        settings: Settings,
        chats: ChatRepository,
        provider: AudioProvider,
    ) -> None:
        self._settings = settings
        self._chats = chats
        self._provider = provider

    async def transcribe(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        incoming: IncomingAudio,
        *,
        language_hint: str | None,
    ) -> VoiceTranscriptionResponse:
        if await self._chats.get_chat(farmer_id, chat_id) is None:
            raise ApplicationError(code="CHAT_NOT_FOUND", status_code=404)
        if not incoming.content:
            raise ApplicationError(code="VOICE_AUDIO_REQUIRED", status_code=422)
        if len(incoming.content) > self._settings.voice_max_audio_bytes:
            raise ApplicationError(code="VOICE_AUDIO_TOO_LARGE", status_code=413)
        suffix = Path(incoming.filename).suffix.casefold()
        if suffix not in self._SUPPORTED_TRANSCRIPTION_SUFFIXES:
            raise ApplicationError(code="VOICE_AUDIO_FORMAT_UNSUPPORTED", status_code=422)
        if not self._matches_audio_container(suffix, incoming.content):
            raise ApplicationError(code="VOICE_AUDIO_CONTENT_INVALID", status_code=422)
        result = await self._provider.transcribe(
            AudioTranscriptionRequest(
                filename=f"recording{suffix}",
                content_type=incoming.content_type,
                content=incoming.content,
                language_hint=language_hint,
            )
        )
        if len(result.text) > self._settings.voice_max_transcript_characters:
            raise ApplicationError(code="VOICE_TRANSCRIPT_TOO_LONG", status_code=422)
        return VoiceTranscriptionResponse(transcript=result.text)

    async def speech(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        message_id: UUID,
    ) -> SpeechSynthesisResult:
        stream = await self.speech_stream(farmer_id, chat_id, message_id)
        parts = [chunk async for chunk in stream.content]
        if not parts:
            raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)
        return SpeechSynthesisResult(
            content=b"".join(parts),
            media_type=stream.media_type,
            model=stream.model,
            voice=stream.voice,
        )

    async def speech_stream(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        message_id: UUID,
    ) -> SpeechSynthesisStream:
        message = await self._chats.message(farmer_id, chat_id, message_id)
        if message is None or message.role != "assistant":
            raise ApplicationError(code="CHAT_MESSAGE_NOT_FOUND", status_code=404)
        if len(message.content) > self._settings.voice_max_speech_characters:
            raise ApplicationError(code="VOICE_TEXT_TOO_LONG", status_code=422)
        text_chunks = self._speech_chunks(message.content)
        first = await self._provider.synthesize_stream(SpeechSynthesisRequest(text=text_chunks[0]))

        async def content() -> AsyncIterator[bytes]:
            emitted = False
            for index, text in enumerate(text_chunks):
                result = (
                    first
                    if index == 0
                    else await self._provider.synthesize_stream(SpeechSynthesisRequest(text=text))
                )
                if (
                    result.media_type != first.media_type
                    or result.model != first.model
                    or result.voice != first.voice
                ):
                    raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502)
                stream = result.content
                if index > 0 and result.media_type == "audio/mpeg":
                    stream = self._without_leading_id3(stream)
                async for chunk in stream:
                    if chunk:
                        emitted = True
                        yield chunk
            if not emitted:
                raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)

        return SpeechSynthesisStream(
            content=content(),
            media_type=first.media_type,
            model=first.model,
            voice=first.voice,
        )

    @classmethod
    def _speech_chunks(cls, text: str) -> list[str]:
        """Split long replies at natural boundaries before provider limits."""

        remaining = text.strip()
        chunks: list[str] = []
        while len(remaining) > cls._PROVIDER_SPEECH_CHUNK_CHARACTERS:
            window = remaining[: cls._PROVIDER_SPEECH_CHUNK_CHARACTERS]
            floor = cls._PROVIDER_SPEECH_CHUNK_CHARACTERS // 2
            split_at = max(
                window.rfind(separator, floor)
                for separator in ("। ", ". ", "? ", "! ", "\n", ", ", " ")
            )
            if split_at < floor:
                split_at = cls._PROVIDER_SPEECH_CHUNK_CHARACTERS
            else:
                split_at += 1
            chunk = remaining[:split_at].strip()
            if chunk:
                chunks.append(chunk)
            remaining = remaining[split_at:].strip()
        if remaining:
            chunks.append(remaining)
        if not chunks:
            raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)
        return chunks

    @staticmethod
    def _join_audio(results: list[SpeechSynthesisResult]) -> bytes:
        """Join MP3 frame streams while removing repeated intermediate ID3 tags."""

        parts: list[bytes] = []
        for index, result in enumerate(results):
            content = result.content
            if index > 0 and result.media_type == "audio/mpeg" and content.startswith(b"ID3"):
                if len(content) < 10:
                    raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502)
                size = (
                    (content[6] & 0x7F) << 21
                    | (content[7] & 0x7F) << 14
                    | (content[8] & 0x7F) << 7
                    | (content[9] & 0x7F)
                )
                content = content[10 + size :]
            if not content:
                raise ApplicationError(code="VOICE_AUDIO_EMPTY", status_code=502)
            parts.append(content)
        return b"".join(parts)

    @staticmethod
    async def _without_leading_id3(content: AsyncIterator[bytes]) -> AsyncIterator[bytes]:
        """Remove one leading ID3 block before concatenating another MP3 stream."""

        buffered = bytearray()
        stripped = False
        async for chunk in content:
            if stripped:
                yield chunk
                continue
            buffered.extend(chunk)
            if len(buffered) < 10:
                continue
            if not buffered.startswith(b"ID3"):
                stripped = True
                yield bytes(buffered)
                buffered.clear()
                continue
            size = (
                (buffered[6] & 0x7F) << 21
                | (buffered[7] & 0x7F) << 14
                | (buffered[8] & 0x7F) << 7
                | (buffered[9] & 0x7F)
            )
            header_size = 10 + size
            if len(buffered) < header_size:
                continue
            stripped = True
            remainder = bytes(buffered[header_size:])
            buffered.clear()
            if remainder:
                yield remainder
        if not stripped and buffered:
            if buffered.startswith(b"ID3"):
                raise ApplicationError(code="VOICE_PROVIDER_FAILED", status_code=502)
            yield bytes(buffered)
