"""Durable ordered worker for queued farmer chat turns."""

import asyncio
from contextlib import suppress

import structlog

from app.core.config import Settings
from app.database.session import DatabasePort
from app.integrations.llm.provider import LLMProvider
from app.integrations.memory.provider import MemoryProvider
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider
from app.modules.chats.dependencies import build_chat_service
from app.modules.chats.service import ChatTurnClaim


class ChatTurnWorker:
    def __init__(
        self,
        *,
        settings: Settings,
        database: DatabasePort,
        llm_provider: LLMProvider,
        memory_provider: MemoryProvider,
        current_weather_provider: CurrentWeatherProvider,
        forecast_weather_provider: ForecastWeatherProvider,
    ) -> None:
        self._settings = settings
        self._database = database
        self._llm_provider = llm_provider
        self._memory_provider = memory_provider
        self._current_weather_provider = current_weather_provider
        self._forecast_weather_provider = forecast_weather_provider
        self._stop = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._logger = structlog.get_logger(__name__)

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="chat-turn-worker")

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
                    service = build_chat_service(
                        settings=self._settings,
                        session=session,
                        database=self._database,
                        llm_provider=self._llm_provider,
                        memory_provider=self._memory_provider,
                        current_weather_provider=self._current_weather_provider,
                        forecast_weather_provider=self._forecast_weather_provider,
                    )
                    claims = await service.claim_due_turns(
                        limit=self._settings.chat_turn_batch_size,
                        lease_seconds=self._settings.chat_turn_lease_seconds,
                    )
                await asyncio.gather(*(self._process(claim) for claim in claims))
                if claims:
                    self._logger.info("chat_turn.batch_processed", turns=len(claims))
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._logger.warning("chat_turn.worker_failed", error_type=type(exc).__name__)
            with suppress(TimeoutError):
                await asyncio.wait_for(
                    self._stop.wait(),
                    timeout=self._settings.chat_turn_interval_seconds,
                )

    async def _process(self, claim: ChatTurnClaim) -> None:
        async with self._database.session() as session:
            service = build_chat_service(
                settings=self._settings,
                session=session,
                database=self._database,
                llm_provider=self._llm_provider,
                memory_provider=self._memory_provider,
                current_weather_provider=self._current_weather_provider,
                forecast_weather_provider=self._forecast_weather_provider,
            )
            await service.process_claimed_turn(
                claim,
                max_attempts=self._settings.chat_turn_max_attempts,
                processing_timeout_seconds=(
                    self._settings.chat_turn_processing_timeout_seconds
                ),
                backoff_base_seconds=self._settings.chat_turn_backoff_base_seconds,
                backoff_max_seconds=self._settings.chat_turn_backoff_max_seconds,
            )
