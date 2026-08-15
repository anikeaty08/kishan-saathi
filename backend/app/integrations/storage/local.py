"""Local private object storage for development and hackathon use."""

import asyncio
import os
from pathlib import Path
from uuid import UUID, uuid4

from app.core.errors import ApplicationError
from app.integrations.storage.provider import ObjectStorageProvider, StoredObject


class LocalObjectStorage(ObjectStorageProvider):
    """Store opaque JPEG objects under an owner-isolated local directory."""

    def __init__(self, root: str | Path) -> None:
        self._root = Path(root).resolve()

    async def put_private_image(
        self,
        *,
        owner_id: UUID,
        category: str,
        content: bytes,
    ) -> StoredObject:
        safe_category = self._safe_segment(category)
        key = f"{owner_id}/{safe_category}/{uuid4()}.jpg"
        target = self._owned_path(owner_id, key)
        try:
            await asyncio.to_thread(self._atomic_write, target, content)
        except OSError as exc:
            raise ApplicationError(code="STORAGE_WRITE_FAILED", status_code=503) from exc
        return StoredObject(key=key, size_bytes=len(content), media_type="image/jpeg")

    async def read_private(self, *, owner_id: UUID, key: str) -> bytes:
        try:
            target = self._owned_path(owner_id, key)
            return await asyncio.to_thread(target.read_bytes)
        except (FileNotFoundError, ValueError) as exc:
            raise ApplicationError(code="STORAGE_OBJECT_NOT_FOUND", status_code=404) from exc
        except OSError as exc:
            raise ApplicationError(code="STORAGE_READ_FAILED", status_code=503) from exc

    async def delete_private(self, *, owner_id: UUID, key: str) -> None:
        try:
            target = self._owned_path(owner_id, key)
            await asyncio.to_thread(target.unlink, missing_ok=True)
        except ValueError as exc:
            raise ApplicationError(code="STORAGE_OBJECT_NOT_FOUND", status_code=404) from exc
        except OSError as exc:
            raise ApplicationError(code="STORAGE_DELETE_FAILED", status_code=503) from exc

    async def close(self) -> None:
        return None

    def _owned_path(self, owner_id: UUID, key: str) -> Path:
        expected_prefix = f"{owner_id}/"
        if not key.startswith(expected_prefix):
            raise ValueError("Object key does not belong to owner")
        target = (self._root / key).resolve()
        owner_root = (self._root / str(owner_id)).resolve()
        if not target.is_relative_to(owner_root):
            raise ValueError("Invalid object key")
        return target

    @staticmethod
    def _safe_segment(value: str) -> str:
        if not value or not value.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Invalid object category")
        return value

    @staticmethod
    def _atomic_write(target: Path, content: bytes) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(f".{uuid4()}.tmp")
        try:
            temporary.write_bytes(content)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
