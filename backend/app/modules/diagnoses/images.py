"""Leaf-image validation, privacy sanitization, and compression."""

import asyncio
from dataclasses import dataclass
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import Settings
from app.core.errors import ApplicationError


@dataclass(frozen=True, slots=True)
class PreparedImage:
    """Sanitized JPEG ready for inference and private storage."""

    content: bytes
    width: int
    height: int


class ImagePreprocessor:
    """Validate images, remove EXIF, and constrain storage size."""

    def __init__(self, settings: Settings, *, error_prefix: str = "SCAN_IMAGE") -> None:
        self._max_bytes = settings.max_image_bytes
        self._max_dimension = settings.stored_image_max_dimension
        self._max_pixels = settings.source_image_max_pixels
        self._jpeg_quality = settings.stored_image_jpeg_quality
        self._error_prefix = error_prefix

    async def prepare(self, content: bytes) -> PreparedImage:
        if not content:
            raise ApplicationError(code=f"{self._error_prefix}_EMPTY", status_code=422)
        if len(content) > self._max_bytes:
            raise ApplicationError(code=f"{self._error_prefix}_TOO_LARGE", status_code=413)
        return await asyncio.to_thread(self._prepare_sync, content)

    def _prepare_sync(self, content: bytes) -> PreparedImage:
        try:
            with Image.open(BytesIO(content)) as source:
                width, height = source.size
                if width * height > self._max_pixels:
                    raise ApplicationError(
                        code=f"{self._error_prefix}_PIXELS_EXCEEDED",
                        status_code=413,
                    )
                source.verify()
            with Image.open(BytesIO(content)) as source:
                oriented = ImageOps.exif_transpose(source)
                rgb = oriented.convert("RGB")
                rgb.thumbnail((self._max_dimension, self._max_dimension), Image.Resampling.LANCZOS)
                width, height = rgb.size
                output = BytesIO()
                rgb.save(
                    output,
                    format="JPEG",
                    quality=self._jpeg_quality,
                    optimize=True,
                )
        except ApplicationError:
            raise
        except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError) as exc:
            raise ApplicationError(code=f"{self._error_prefix}_INVALID", status_code=422) from exc
        if width < 32 or height < 32:
            raise ApplicationError(code=f"{self._error_prefix}_TOO_SMALL", status_code=422)
        return PreparedImage(content=output.getvalue(), width=width, height=height)
