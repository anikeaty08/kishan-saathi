"""Authenticated request-based speech endpoints for Saathi chat."""

from collections.abc import AsyncIterator
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import StreamingResponse

from app.core.config import Settings
from app.core.dependencies import get_app_settings, get_paid_operation_rate_limiter
from app.core.errors import ApplicationError
from app.core.rate_limits import PaidOperationRateLimiter
from app.modules.users.dependencies import get_current_farmer_id
from app.modules.voice.dependencies import get_voice_service
from app.modules.voice.schemas import VoiceTranscriptionResponse
from app.modules.voice.service import IncomingAudio, VoiceService

router = APIRouter(prefix="/voice", tags=["saathi-voice"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[VoiceService, Depends(get_voice_service)]


@router.post("/chats/{chat_id}/transcriptions", response_model=VoiceTranscriptionResponse)
async def transcribe_chat_audio(
    chat_id: UUID,
    audio: Annotated[UploadFile, File()],
    farmer_id: FarmerId,
    service: Service,
    settings: Annotated[Settings, Depends(get_app_settings)],
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
    language_hint: Annotated[str | None, Form(pattern=r"^[a-z]{2}$")] = None,
) -> VoiceTranscriptionResponse:
    async with limiter.request(farmer_id, "transcription"):
        filename = audio.filename or "recording.m4a"
        content_type = audio.content_type or "application/octet-stream"
        try:
            content = await audio.read(settings.voice_max_audio_bytes + 1)
        finally:
            await audio.close()
        if len(content) > settings.voice_max_audio_bytes:
            raise ApplicationError(code="VOICE_AUDIO_TOO_LARGE", status_code=413)
        return await service.transcribe(
            farmer_id,
            chat_id,
            IncomingAudio(
                filename=filename,
                content_type=content_type,
                content=content,
            ),
            language_hint=language_hint,
        )


@router.get(
    "/chats/{chat_id}/messages/{message_id}/speech",
    operation_id="stream_assistant_message_speech",
)
@router.post(
    "/chats/{chat_id}/messages/{message_id}/speech",
    operation_id="speak_assistant_message",
)
async def speak_assistant_message(
    chat_id: UUID,
    message_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
) -> StreamingResponse:
    result = await service.speech_stream(farmer_id, chat_id, message_id)

    async def audio() -> AsyncIterator[bytes]:
        async with limiter.request(farmer_id, "speech"):
            async for chunk in result.content:
                yield chunk

    return StreamingResponse(
        content=audio(),
        media_type=result.media_type,
        headers={
            "Cache-Control": "private, no-store",
            "X-AI-Generated-Voice": "true",
            "X-Voice-Model": result.model,
        },
    )
