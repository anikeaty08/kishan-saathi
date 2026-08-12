"""Request-scoped history dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db_session
from app.modules.farms.repository import FarmRepository
from app.modules.history.repository import HistoryRepository
from app.modules.history.service import HistoryService


def get_history_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> HistoryService:
    return HistoryService(HistoryRepository(session), FarmRepository(session))
