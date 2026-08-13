"""Process-local paid-provider rate and concurrency controls."""

import asyncio
from collections import defaultdict, deque
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from time import monotonic
from typing import Literal
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError

PaidOperation = Literal["transcription", "speech", "progression", "memory_connection"]


class PaidOperationRateLimiter:
    """Bound per-farmer paid calls; deployment edge limits still protect all replicas."""

    def __init__(self, settings: Settings) -> None:
        self._limits: dict[PaidOperation, int] = {
            "transcription": settings.voice_transcriptions_per_minute,
            "speech": settings.voice_speech_requests_per_minute,
            "progression": settings.progression_requests_per_minute,
            "memory_connection": settings.memory_connections_per_minute,
        }
        self._concurrency = asyncio.Semaphore(settings.paid_provider_max_concurrent_requests)
        self._lock = asyncio.Lock()
        self._events: dict[tuple[UUID, PaidOperation], deque[float]] = defaultdict(deque)

    @asynccontextmanager
    async def request(
        self,
        farmer_id: UUID,
        operation: PaidOperation,
    ) -> AsyncIterator[None]:
        now = monotonic()
        key = (farmer_id, operation)
        async with self._lock:
            events = self._events[key]
            while events and events[0] <= now - 60:
                events.popleft()
            if len(events) >= self._limits[operation]:
                raise ApplicationError(code="PROVIDER_RATE_LIMITED", status_code=429)
            events.append(now)
        try:
            await asyncio.wait_for(self._concurrency.acquire(), timeout=0.25)
        except TimeoutError as exc:
            raise ApplicationError(code="PROVIDER_BUSY", status_code=503) from exc
        try:
            yield
        finally:
            self._concurrency.release()
