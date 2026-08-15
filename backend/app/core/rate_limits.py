"""Process-local paid-provider rate and concurrency controls."""

import asyncio
import hashlib
import hmac
from collections import defaultdict, deque
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from time import monotonic
from typing import Literal
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.session import DatabasePort
from app.modules.usage.models import AuthRateLimitBucket, ProviderRateLimitBucket

PaidOperation = Literal[
    "transcription",
    "speech",
    "progression",
    "memory_connection",
    "diagnosis",
    "chat",
    "weather",
]


class PaidOperationRateLimiter:
    """Bound per-farmer paid calls; deployment edge limits still protect all replicas."""

    def __init__(self, settings: Settings, database: DatabasePort | None = None) -> None:
        self._limits: dict[PaidOperation, int] = {
            "transcription": settings.voice_transcriptions_per_minute,
            "speech": settings.voice_speech_requests_per_minute,
            "progression": settings.progression_requests_per_minute,
            "memory_connection": settings.memory_connections_per_minute,
            "diagnosis": settings.diagnosis_requests_per_minute,
            "chat": settings.chat_requests_per_minute,
            "weather": settings.weather_requests_per_minute,
        }
        self._concurrency = asyncio.Semaphore(settings.paid_provider_max_concurrent_requests)
        self._lock = asyncio.Lock()
        self._events: dict[tuple[UUID, PaidOperation], deque[float]] = defaultdict(deque)
        self._database = database

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
        if self._database is not None:
            await self._reserve_shared(farmer_id, operation, self._limits[operation])
        try:
            await asyncio.wait_for(self._concurrency.acquire(), timeout=0.25)
        except TimeoutError as exc:
            raise ApplicationError(code="PROVIDER_BUSY", status_code=503) from exc
        try:
            yield
        finally:
            self._concurrency.release()

    async def _reserve_shared(
        self, farmer_id: UUID, operation: PaidOperation, limit: int
    ) -> None:
        database = self._database
        if database is None:
            return
        window_start = datetime.now(tz=UTC).replace(second=0, microsecond=0)
        try:
            async with database.session() as session:
                dialect = session.bind.dialect.name if session.bind is not None else ""
                values = {
                    "farmer_id": farmer_id,
                    "operation": operation,
                    "window_start": window_start,
                    "request_count": 1,
                }
                if dialect == "postgresql":
                    from sqlalchemy.dialects.postgresql import insert as pg_insert

                    statement = (
                        pg_insert(ProviderRateLimitBucket)
                        .values(**values)
                        .on_conflict_do_update(
                            index_elements=["farmer_id", "operation", "window_start"],
                            set_={
                                "request_count": ProviderRateLimitBucket.request_count + 1,
                            },
                            where=ProviderRateLimitBucket.request_count < limit,
                        )
                        .returning(ProviderRateLimitBucket.request_count)
                    )
                elif dialect == "sqlite":
                    from sqlalchemy.dialects.sqlite import insert as sqlite_insert

                    statement = (
                        sqlite_insert(ProviderRateLimitBucket)
                        .values(**values)
                        .on_conflict_do_update(
                            index_elements=["farmer_id", "operation", "window_start"],
                            set_={
                                "request_count": ProviderRateLimitBucket.request_count + 1,
                            },
                            where=ProviderRateLimitBucket.request_count < limit,
                        )
                        .returning(ProviderRateLimitBucket.request_count)
                    )
                else:
                    raise RuntimeError("RATE_LIMIT_DATABASE_DIALECT_UNSUPPORTED")
                reserved = await session.scalar(statement)
                if reserved is None:
                    await session.rollback()
                    raise ApplicationError(code="PROVIDER_RATE_LIMITED", status_code=429)
                await session.commit()
        except ApplicationError:
            raise
        except Exception as exc:
            raise ApplicationError(code="PROVIDER_QUOTA_UNAVAILABLE", status_code=503) from exc


class AuthRateLimiter:
    """Cross-replica account/IP throttling before Cognito is contacted."""

    def __init__(self, settings: Settings, database: DatabasePort | None = None) -> None:
        self._limit = settings.auth_requests_per_minute
        self._ip_limit = settings.auth_ip_requests_per_minute
        configured_key = settings.auth_rate_limit_hmac_key.get_secret_value()
        self._hmac_key = (
            configured_key or "development-only-auth-rate-limit-key"
        ).encode()
        self._database = database
        self._lock = asyncio.Lock()
        self._events: dict[UUID, deque[float]] = defaultdict(deque)

    def subject_key(self, value: str) -> UUID:
        """Return a non-reversible stable bucket key without storing PII."""

        digest = hmac.new(self._hmac_key, value.encode(), hashlib.sha256).digest()
        return UUID(bytes=digest[:16])

    @asynccontextmanager
    async def request(
        self, subject_key: UUID, *, limit: int | None = None
    ) -> AsyncIterator[None]:
        resolved_limit = limit or self._limit
        now = monotonic()
        async with self._lock:
            events = self._events[subject_key]
            while events and events[0] <= now - 60:
                events.popleft()
            if len(events) >= resolved_limit:
                raise ApplicationError(code="AUTH_RATE_LIMITED", status_code=429)
            events.append(now)
        if self._database is not None:
            await self._reserve_shared(subject_key, resolved_limit)
        yield

    @asynccontextmanager
    async def ip_request(self, subject_key: UUID) -> AsyncIterator[None]:
        async with self.request(subject_key, limit=self._ip_limit):
            yield

    async def _reserve_shared(self, subject_key: UUID, limit: int) -> None:
        database = self._database
        if database is None:
            return
        window_start = datetime.now(tz=UTC).replace(second=0, microsecond=0)
        values = {
            "subject_key": subject_key,
            "window_start": window_start,
            "request_count": 1,
        }
        try:
            async with database.session() as session:
                dialect = session.bind.dialect.name if session.bind is not None else ""
                if dialect == "postgresql":
                    from sqlalchemy.dialects.postgresql import insert as pg_insert

                    statement = (
                        pg_insert(AuthRateLimitBucket)
                        .values(**values)
                        .on_conflict_do_update(
                            index_elements=["subject_key", "window_start"],
                            set_={"request_count": AuthRateLimitBucket.request_count + 1},
                            where=AuthRateLimitBucket.request_count < limit,
                        )
                        .returning(AuthRateLimitBucket.request_count)
                    )
                elif dialect == "sqlite":
                    from sqlalchemy.dialects.sqlite import insert as sqlite_insert

                    statement = (
                        sqlite_insert(AuthRateLimitBucket)
                        .values(**values)
                        .on_conflict_do_update(
                            index_elements=["subject_key", "window_start"],
                            set_={"request_count": AuthRateLimitBucket.request_count + 1},
                            where=AuthRateLimitBucket.request_count < limit,
                        )
                        .returning(AuthRateLimitBucket.request_count)
                    )
                else:
                    raise RuntimeError("RATE_LIMIT_DATABASE_DIALECT_UNSUPPORTED")
                reserved = await session.scalar(statement)
                if reserved is None:
                    await session.rollback()
                    raise ApplicationError(code="AUTH_RATE_LIMITED", status_code=429)
                await session.commit()
        except ApplicationError:
            raise
        except Exception as exc:
            raise ApplicationError(code="AUTH_QUOTA_UNAVAILABLE", status_code=503) from exc
