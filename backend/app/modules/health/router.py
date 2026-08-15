"""Liveness and readiness HTTP endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.core.config import Settings
from app.core.dependencies import (
    get_app_settings,
    get_database,
    get_leaf_inference_provider,
)
from app.database.session import DatabasePort
from app.integrations.inference.provider import (
    LeafInferenceProvider,
    UnavailableLeafInferenceProvider,
)
from app.modules.health.schemas import HealthResponse, HealthStatus
from app.modules.health.service import HealthService

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", response_model=HealthResponse)
async def liveness(
    settings: Annotated[Settings, Depends(get_app_settings)],
    database: Annotated[DatabasePort, Depends(get_database)],
) -> HealthResponse:
    """Return process liveness without contacting external dependencies."""

    return HealthService(settings, database).liveness()


@router.get(
    "/ready",
    response_model=HealthResponse,
    responses={status.HTTP_503_SERVICE_UNAVAILABLE: {"model": HealthResponse}},
)
async def readiness(
    response: Response,
    settings: Annotated[Settings, Depends(get_app_settings)],
    database: Annotated[DatabasePort, Depends(get_database)],
    leaf_inference: Annotated[LeafInferenceProvider, Depends(get_leaf_inference_provider)],
) -> HealthResponse:
    """Return whether dependencies required for normal traffic are available."""

    result = await HealthService(
        settings,
        database,
        leaf_inference_available=not isinstance(leaf_inference, UnavailableLeafInferenceProvider),
    ).readiness()
    if result.status is HealthStatus.NOT_READY:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return result
