"""Request-scoped voice dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import get_app_settings, get_audio_provider, get_db_session
from app.integrations.audio.provider import AudioProvider
from app.modules.chats.repository import ChatRepository
from app.modules.voice.service import VoiceService


def get_voice_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    provider: Annotated[AudioProvider, Depends(get_audio_provider)],
) -> VoiceService:
    return VoiceService(settings=settings, chats=ChatRepository(session), provider=provider)
