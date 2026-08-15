"""Request-scoped reminder dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db_session
from app.modules.chats.repository import ChatRepository
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.service import ReminderService


def get_reminder_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> ReminderService:
    return ReminderService(
        repository=ReminderRepository(session),
        farms=FarmRepository(session),
        diagnoses=DiagnosisRepository(session),
        chats=ChatRepository(session),
    )
