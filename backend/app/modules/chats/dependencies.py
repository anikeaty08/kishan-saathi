"""Request-scoped chat dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import (
    get_app_settings,
    get_db_session,
    get_llm_provider,
    get_memory_provider,
)
from app.integrations.llm.provider import LLMProvider
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider
from app.modules.chats.repository import ChatRepository
from app.modules.chats.service import ChatService
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository


def get_chat_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    llm_provider: Annotated[LLMProvider, Depends(get_llm_provider)],
    memory_provider: Annotated[MemoryProvider, Depends(get_memory_provider)],
) -> ChatService:
    return ChatService(
        repository=ChatRepository(session),
        farms=FarmRepository(session),
        diagnoses=DiagnosisRepository(session),
        memory=memory_provider,
        llm=LLMRouter(llm_provider, settings),
    )
