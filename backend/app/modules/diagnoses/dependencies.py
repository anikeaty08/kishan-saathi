"""Request-scoped diagnosis dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import (
    get_app_settings,
    get_db_session,
    get_leaf_inference_provider,
    get_object_storage,
)
from app.integrations.inference.provider import LeafInferenceProvider
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.diagnoses.service import DiagnosisService
from app.modules.farms.repository import FarmRepository


def get_diagnosis_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    storage: Annotated[ObjectStorageProvider, Depends(get_object_storage)],
    inference: Annotated[LeafInferenceProvider, Depends(get_leaf_inference_provider)],
) -> DiagnosisService:
    return DiagnosisService(
        settings=settings,
        repository=DiagnosisRepository(session),
        farm_repository=FarmRepository(session),
        storage=storage,
        inference=inference,
    )
