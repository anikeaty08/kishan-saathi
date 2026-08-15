"""Request-scoped farm-module dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import get_app_settings, get_db_session, get_object_storage
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.farms.photos import ActivityPhotoService
from app.modules.farms.repository import FarmRepository
from app.modules.farms.service import FarmService
from app.modules.storage_cleanup.service import ObjectCleanupService


def get_farm_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> FarmService:
    return FarmService(FarmRepository(session))


def get_activity_photo_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    storage: Annotated[ObjectStorageProvider, Depends(get_object_storage)],
) -> ActivityPhotoService:
    return ActivityPhotoService(
        settings=settings,
        repository=FarmRepository(session),
        storage=storage,
        cleanup=ObjectCleanupService(
            session,
            storage,
            backoff_base_seconds=settings.object_cleanup_backoff_base_seconds,
            backoff_max_seconds=settings.object_cleanup_backoff_max_seconds,
        ),
    )
