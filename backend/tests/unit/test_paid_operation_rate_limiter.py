"""Cost-control tests for paid provider operations."""

from uuid import uuid4

import pytest

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.core.rate_limits import PaidOperationRateLimiter


@pytest.mark.asyncio
async def test_rate_limit_is_scoped_by_farmer_and_operation() -> None:
    limiter = PaidOperationRateLimiter(
        Settings(
            _env_file=None,
            progression_requests_per_minute=1,
            voice_speech_requests_per_minute=1,
        )
    )
    farmer_id = uuid4()

    async with limiter.request(farmer_id, "progression"):
        pass
    async with limiter.request(farmer_id, "speech"):
        pass
    async with limiter.request(uuid4(), "progression"):
        pass

    with pytest.raises(ApplicationError) as caught:
        async with limiter.request(farmer_id, "progression"):
            pass

    assert caught.value.code == "PROVIDER_RATE_LIMITED"
    assert caught.value.status_code == 429


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
