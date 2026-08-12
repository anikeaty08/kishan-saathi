"""Tests for owner-isolated local object storage."""

from pathlib import Path
from uuid import UUID

import pytest

from app.integrations.storage.local import LocalObjectStorage

OWNER = UUID("00000000-0000-0000-0000-000000000001")
OTHER = UUID("00000000-0000-0000-0000-000000000002")


@pytest.mark.asyncio
async def test_local_storage_round_trip_and_owner_isolation(tmp_path: Path) -> None:
    storage = LocalObjectStorage(tmp_path)
    stored = await storage.put_private_image(
        owner_id=OWNER,
        category="leaf-scans",
        content=b"private image",
    )

    assert await storage.read_private(owner_id=OWNER, key=stored.key) == b"private image"
    with pytest.raises(ValueError):
        await storage.read_private(owner_id=OTHER, key=stored.key)

    await storage.delete_private(owner_id=OWNER, key=stored.key)
    with pytest.raises(FileNotFoundError):
        await storage.read_private(owner_id=OWNER, key=stored.key)
