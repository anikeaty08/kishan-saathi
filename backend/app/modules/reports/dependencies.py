"""Request-scoped report dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import get_app_settings, get_db_session, get_object_storage
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reports.repository import ReportRepository
from app.modules.reports.service import ReportService
from app.modules.storage_cleanup.service import ObjectCleanupService


def get_report_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    storage: Annotated[ObjectStorageProvider, Depends(get_object_storage)],
) -> ReportService:
    return ReportService(
        repository=ReportRepository(session),
        diagnoses=DiagnosisRepository(session),
        farms=FarmRepository(session),
        storage=storage,
        cleanup=ObjectCleanupService(
            session,
            storage,
            backoff_base_seconds=settings.object_cleanup_backoff_base_seconds,
            backoff_max_seconds=settings.object_cleanup_backoff_max_seconds,
        ),
    )
