"""Automatic retry worker for scoped-memory capture jobs."""

import asyncio
from contextlib import suppress

import structlog

from app.core.config import Settings
from app.database.session import DatabasePort
from app.integrations.llm.provider import LLMProvider
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider
from app.modules.chats.repository import ChatRepository
from app.modules.farms.repository import FarmRepository
from app.modules.memories.repository import MemoryRepository
from app.modules.memories.service import MemoryService


class MemoryCaptureWorker:
    def __init__(
        self,
        *,
        settings: Settings,
        database: DatabasePort,
        llm_provider: LLMProvider,
        memory_provider: MemoryProvider,
    ) -> None:
        self._settings = settings
        self._database = database
        self._llm_provider = llm_provider
        self._memory_provider = memory_provider
        self._stop = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._logger = structlog.get_logger(__name__)

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="memory-capture-worker")

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
                    service = MemoryService(
                        repository=MemoryRepository(session),
                        chats=ChatRepository(session),
                        farms=FarmRepository(session),
                        provider=self._memory_provider,
                        llm=LLMRouter(self._llm_provider, self._settings),
                        max_capture_attempts=self._settings.memory_capture_max_attempts,
                    )
                    processed = await service.process_due_capture_jobs(
                        limit=self._settings.memory_capture_batch_size
                    )
                if processed:
                    self._logger.info("memory_capture.batch_processed", jobs=processed)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._logger.warning("memory_capture.worker_failed", error_type=type(exc).__name__)
            with suppress(TimeoutError):
                await asyncio.wait_for(
                    self._stop.wait(),
                    timeout=self._settings.memory_capture_interval_seconds,
                )
