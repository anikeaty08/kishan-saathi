"""Liveness and readiness HTTP endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.core.config import Settings
from app.core.dependencies import get_app_settings, get_database
from app.database.session import DatabasePort
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
) -> HealthResponse:
    """Return whether dependencies required for normal traffic are available."""

    result = await HealthService(settings, database).readiness()
    if result.status is HealthStatus.NOT_READY:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return result
