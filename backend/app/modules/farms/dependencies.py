"""Request-scoped farm-module dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db_session
from app.modules.farms.repository import FarmRepository
from app.modules.farms.service import FarmService


def get_farm_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> FarmService:
    return FarmService(FarmRepository(session))
