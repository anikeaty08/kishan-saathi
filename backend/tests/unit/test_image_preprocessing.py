"""Tests for private leaf-image preparation."""

from io import BytesIO

import pytest
from PIL import Image

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.modules.diagnoses.images import ImagePreprocessor


@pytest.mark.asyncio
async def test_preprocessor_removes_exif_and_constrains_dimensions() -> None:
    source = Image.new("RGB", (3000, 1500), color=(20, 120, 40))
    exif = Image.Exif()
    exif[0x010F] = "Private Phone Model"
    raw = BytesIO()
    source.save(raw, format="JPEG", exif=exif)
    settings = Settings(_env_file=None, stored_image_max_dimension=1024)

    prepared = await ImagePreprocessor(settings).prepare(raw.getvalue())

    with Image.open(BytesIO(prepared.content)) as saved:
        assert saved.format == "JPEG"
        assert saved.getexif() == {}
        assert max(saved.size) == 1024
    assert (prepared.width, prepared.height) == (1024, 512)


@pytest.mark.asyncio
async def test_preprocessor_rejects_non_image_and_tiny_image() -> None:
    preprocessor = ImagePreprocessor(Settings(_env_file=None))
    with pytest.raises(ApplicationError) as invalid:
        await preprocessor.prepare(b"not an image")

    tiny = BytesIO()
    Image.new("RGB", (10, 10)).save(tiny, format="PNG")
    with pytest.raises(ApplicationError) as too_small:
        await preprocessor.prepare(tiny.getvalue())

    assert invalid.value.code == "SCAN_IMAGE_INVALID"
    assert too_small.value.code == "SCAN_IMAGE_TOO_SMALL"


@pytest.mark.asyncio
async def test_preprocessor_rejects_excessive_source_pixels_before_decode() -> None:
    raw = BytesIO()
    Image.new("RGB", (1001, 1000)).save(raw, format="PNG")
    preprocessor = ImagePreprocessor(Settings(_env_file=None, source_image_max_pixels=1_000_000))

    with pytest.raises(ApplicationError) as raised:
        await preprocessor.prepare(raw.getvalue())

    assert raised.value.code == "SCAN_IMAGE_PIXELS_EXCEEDED"
