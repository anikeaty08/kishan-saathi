"""Background retention worker for expired public diagnosis reports."""

import asyncio
from contextlib import suppress

import structlog

from app.core.config import Settings
from app.database.session import DatabasePort
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.reports.retention import ReportRetentionService
from app.modules.storage_cleanup.service import ObjectCleanupService


class ReportRetentionWorker:
    def __init__(
        self,
        *,
        settings: Settings,
        database: DatabasePort,
        storage: ObjectStorageProvider,
    ) -> None:
        self._settings = settings
        self._database = database
        self._storage = storage
        self._stop = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._logger = structlog.get_logger(__name__)

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="report-retention-worker")

    async def stop(self) -> None:
        self._stop.set()
        if self._task is not None:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
            self._task = None

    async def _run(self) -> None:
        while not self._stop.is_set():
            try:
                async with self._database.session() as session:
                    cleanup = ObjectCleanupService(
                        session,
                        self._storage,
                        backoff_base_seconds=(
                            self._settings.object_cleanup_backoff_base_seconds
                        ),
                        backoff_max_seconds=(
                            self._settings.object_cleanup_backoff_max_seconds
                        ),
                    )
                    processed = await ReportRetentionService(
                        session, cleanup
                    ).expire_due(limit=self._settings.object_cleanup_batch_size)
                if processed:
                    self._logger.info("report_retention.batch_processed", reports=processed)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._logger.warning(
                    "report_retention.worker_failed", error_type=type(exc).__name__
                )
            with suppress(TimeoutError):
                await asyncio.wait_for(
                    self._stop.wait(),
                    timeout=self._settings.object_cleanup_interval_seconds,
                )
