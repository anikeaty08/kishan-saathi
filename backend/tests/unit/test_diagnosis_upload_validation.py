"""Boundary tests for client-supplied diagnosis capture timestamps."""

from datetime import UTC, datetime, timedelta
from io import BytesIO

import pytest
from fastapi import UploadFile

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.modules.diagnoses.router import _read_images


@pytest.mark.asyncio
async def test_capture_timestamp_requires_timezone() -> None:
    upload = UploadFile(file=BytesIO(b"image"), filename="leaf.jpg")
    with pytest.raises(ApplicationError) as caught:
        await _read_images(
            [upload],
            [datetime.now()],
            Settings(_env_file=None),
        )
    assert caught.value.code == "SCAN_IMAGE_TIMESTAMP_TIMEZONE_REQUIRED"


@pytest.mark.asyncio
async def test_capture_timestamp_rejects_unreasonable_future_time() -> None:
    upload = UploadFile(file=BytesIO(b"image"), filename="leaf.jpg")
    with pytest.raises(ApplicationError) as caught:
        await _read_images(
            [upload],
            [datetime.now(tz=UTC) + timedelta(hours=1)],
            Settings(_env_file=None, diagnosis_capture_future_tolerance_minutes=5),
        )
    assert caught.value.code == "SCAN_IMAGE_TIMESTAMP_IN_FUTURE"
