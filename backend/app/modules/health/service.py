"""Readiness checks for required backend dependencies."""

import structlog

from app.core.config import Settings
from app.database.session import DatabasePort
from app.modules.health.schemas import (
    DependencyCheck,
    DependencyStatus,
    HealthResponse,
    HealthStatus,
)


class HealthService:
    """Build process health results while isolating dependency failures."""

    def __init__(self, settings: Settings, database: DatabasePort) -> None:
        self._settings = settings
        self._database = database
        self._logger = structlog.get_logger(__name__)

    def liveness(self) -> HealthResponse:
        """Report that the API process can serve requests."""

        return HealthResponse(
            status=HealthStatus.OK,
            service=self._settings.app_name,
            version=self._settings.app_version,
        )

    async def readiness(self) -> HealthResponse:
        """Report whether all dependencies required for normal traffic work."""

        try:
            await self._database.ping()
        except Exception as exc:
            self._logger.warning(
                "health.database_unavailable",
                error_type=type(exc).__name__,
            )
            return HealthResponse(
                status=HealthStatus.NOT_READY,
                service=self._settings.app_name,
                version=self._settings.app_version,
                checks={"database": DependencyCheck(status=DependencyStatus.DOWN)},
            )

        return HealthResponse(
            status=HealthStatus.OK,
            service=self._settings.app_name,
            version=self._settings.app_version,
            checks={"database": DependencyCheck(status=DependencyStatus.UP)},
        )
