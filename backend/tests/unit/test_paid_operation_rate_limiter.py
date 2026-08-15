"""Cost-control tests for paid provider operations."""

from contextlib import AbstractAsyncContextManager
from pathlib import Path
from typing import cast
from uuid import UUID, uuid4

import pytest
from sqlalchemy import Table
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.core.rate_limits import AuthRateLimiter, PaidOperationRateLimiter
from app.database.base import Base
from app.modules.usage.models import AuthRateLimitBucket, ProviderRateLimitBucket
from app.modules.users.models import FarmerProfile


@pytest.mark.asyncio
async def test_rate_limit_is_scoped_by_farmer_and_operation() -> None:
    limiter = PaidOperationRateLimiter(
        Settings(
            _env_file=None,
            progression_requests_per_minute=1,
            voice_speech_requests_per_minute=1,
            chat_requests_per_minute=1,
            weather_requests_per_minute=1,
        )
    )
    farmer_id = uuid4()

    async with limiter.request(farmer_id, "progression"):
        pass
    async with limiter.request(farmer_id, "speech"):
        pass
    async with limiter.request(uuid4(), "progression"):
        pass
    async with limiter.request(farmer_id, "chat"):
        pass
    async with limiter.request(farmer_id, "weather"):
        pass

    with pytest.raises(ApplicationError) as caught:
        async with limiter.request(farmer_id, "progression"):
            pass

    assert caught.value.code == "PROVIDER_RATE_LIMITED"


@pytest.mark.asyncio
async def test_auth_rate_limit_is_shared_without_a_farmer_row(tmp_path: Path) -> None:
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'auth-quota.db'}")
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=[cast(Table, AuthRateLimitBucket.__table__)],
            )
        )
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    class TestDatabase:
        def session(self) -> AbstractAsyncContextManager[AsyncSession]:
            return sessions()

        async def ping(self) -> None:
            return None

        async def dispose(self) -> None:
            return None

    subject_key = UUID("00000000-0000-0000-0000-000000000456")
    try:
        settings = Settings(_env_file=None, auth_requests_per_minute=1)
        first = AuthRateLimiter(settings, TestDatabase())
        second = AuthRateLimiter(settings, TestDatabase())
        async with first.request(subject_key):
            pass
        with pytest.raises(ApplicationError) as caught:
            async with second.request(subject_key):
                pass
    finally:
        await engine.dispose()

    assert caught.value.code == "AUTH_RATE_LIMITED"
    assert caught.value.status_code == 429


def test_auth_bucket_keys_are_stable_keyed_and_do_not_expose_email() -> None:
    first = AuthRateLimiter(
        Settings(_env_file=None, auth_rate_limit_hmac_key="a" * 32)
    )
    second = AuthRateLimiter(
        Settings(_env_file=None, auth_rate_limit_hmac_key="b" * 32)
    )

    value = "auth-account:farmer@example.com"
    first_key = first.subject_key(value)

    assert first_key == first.subject_key(value)
    assert first_key != second.subject_key(value)
    assert "farmer" not in str(first_key)


@pytest.mark.asyncio
async def test_concurrency_is_released_after_provider_failure() -> None:
    limiter = PaidOperationRateLimiter(
        Settings(_env_file=None, paid_provider_max_concurrent_requests=1)
    )
    farmer_id = uuid4()

    with pytest.raises(RuntimeError, match="provider failed"):
        async with limiter.request(farmer_id, "transcription"):
            raise RuntimeError("provider failed")

    async with limiter.request(farmer_id, "speech"):
        pass


@pytest.mark.asyncio
async def test_rate_limit_is_shared_across_limiter_instances(tmp_path: Path) -> None:
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'quota.db'}")
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=[
                    cast(Table, FarmerProfile.__table__),
                    cast(Table, ProviderRateLimitBucket.__table__),
                ],
            )
        )
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    class TestDatabase:
        def session(self) -> AbstractAsyncContextManager[AsyncSession]:
            return sessions()

        async def ping(self) -> None:
            return None

        async def dispose(self) -> None:
            return None

    farmer_id = UUID("00000000-0000-0000-0000-000000000123")
    try:
        async with sessions() as session:
            session.add(
                FarmerProfile(
                    id=farmer_id,
                    cognito_sub="shared-quota",
                    cognito_username="quota@example.com",
                    email="quota@example.com",
                )
            )
            await session.commit()
        settings = Settings(_env_file=None, chat_requests_per_minute=1)
        first = PaidOperationRateLimiter(settings, TestDatabase())
        second = PaidOperationRateLimiter(settings, TestDatabase())
        async with first.request(farmer_id, "chat"):
            pass
        with pytest.raises(ApplicationError) as caught:
            async with second.request(farmer_id, "chat"):
                pass
    finally:
        await engine.dispose()

    assert caught.value.code == "PROVIDER_RATE_LIMITED"
