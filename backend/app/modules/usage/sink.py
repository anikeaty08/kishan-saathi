"""Independent best-effort persistence for provider usage observations."""

from dataclasses import asdict

import structlog

from app.database.session import DatabasePort
from app.integrations.usage.provider import AIUsageObservation, AIUsageSink
from app.modules.usage.models import AIUsageEvent


class DatabaseAIUsageSink(AIUsageSink):
    """Never let analytics persistence fail the farmer-facing operation."""

    def __init__(self, database: DatabasePort) -> None:
        self._database = database
        self._logger = structlog.get_logger(__name__)

    async def record(self, observation: AIUsageObservation) -> None:
        try:
            async with self._database.session() as session:
                session.add(AIUsageEvent(**asdict(observation)))
                await session.commit()
        except Exception as exc:
            self._logger.warning(
                "ai_usage.persistence_failed",
                operation=observation.operation,
                model=observation.model,
                error_type=type(exc).__name__,
            )
