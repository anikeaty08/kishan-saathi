"""Private activity photo integration coverage."""

from datetime import UTC, datetime
from io import BytesIO
from pathlib import Path
from uuid import UUID

import pytest
from PIL import Image
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.database.base import Base
from app.integrations.storage.local import LocalObjectStorage
from app.modules.farms.models import Activity, Plot
from app.modules.farms.photos import ActivityPhotoService
from app.modules.farms.repository import FarmRepository
from app.modules.storage_cleanup.service import ObjectCleanupService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000081")


@pytest.mark.asyncio
async def test_activity_photo_add_read_remove_and_activity_cleanup(tmp_path: Path) -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    storage = LocalObjectStorage(tmp_path)

    try:
        async with sessions() as session:
            session.add(
                FarmerProfile(
                    id=FARMER,
                    cognito_sub="photos",
                    cognito_username="photos@example.com",
                    email="photos@example.com",
                )
            )
            plot = Plot(
                farmer_id=FARMER,
                name="Photo Plot",
                latitude=18,
                longitude=74,
            )
            session.add(plot)
            await session.flush()
            first = Activity(
                farmer_id=FARMER,
                plot_id=plot.id,
                title="Observed damage",
                occurred_at=datetime.now(tz=UTC),
            )
            second = Activity(
                farmer_id=FARMER,
                plot_id=plot.id,
                title="Observed recovery",
                occurred_at=datetime.now(tz=UTC),
            )
            session.add_all([first, second])
            await session.commit()
            service = ActivityPhotoService(
                settings=Settings(_env_file=None),
                repository=FarmRepository(session),
                storage=storage,
                cleanup=ObjectCleanupService(session, storage),
            )

            photo = await service.add(FARMER, first.id, _image())
            assert (await service.read(FARMER, first.id, photo.id)).startswith(b"\xff\xd8")
            await service.delete(FARMER, first.id, photo.id)

            await service.add(FARMER, second.id, _image())
            await service.delete_activity(FARMER, second.id)
    finally:
        await engine.dispose()

    assert not list(tmp_path.rglob("*.jpg"))


def _image() -> bytes:
    value = BytesIO()
    Image.new("RGB", (300, 200), color=(40, 150, 20)).save(value, format="PNG")
    return value.getvalue()
