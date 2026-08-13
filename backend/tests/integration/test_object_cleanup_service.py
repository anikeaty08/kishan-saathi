"""Durable retry behavior for private object deletion failures."""

import asyncio
from contextlib import AbstractAsyncContextManager
from uuid import UUID

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.database.base import Base
from app.integrations.storage.provider import ObjectStorageProvider, StoredObject
from app.modules.storage_cleanup.models import ObjectDeletionJob
from app.modules.storage_cleanup.service import ObjectCleanupService
from app.modules.storage_cleanup.worker import ObjectCleanupWorker
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-0000000000a1")


class FlakyStorage(ObjectStorageProvider):
    def __init__(self) -> None:
        self.fail = True
        self.deleted = asyncio.Event()

    async def put_private_image(
        self, *, owner_id: UUID, category: str, content: bytes
    ) -> StoredObject:
        raise AssertionError((owner_id, category, content))

    async def read_private(self, *, owner_id: UUID, key: str) -> bytes:
        raise AssertionError((owner_id, key))

    async def delete_private(self, *, owner_id: UUID, key: str) -> None:
        if self.fail:
            raise RuntimeError(f"temporary failure for {owner_id}/{key}")
        self.deleted.set()

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_failed_object_delete_remains_retryable() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    storage = FlakyStorage()
    try:
        async with sessions() as session:
            session.add(
                FarmerProfile(
                    id=FARMER,
                    cognito_sub="cleanup",
                    cognito_username="cleanup@example.com",
                    email="cleanup@example.com",
                )
            )
            await session.commit()
            service = ObjectCleanupService(session, storage)
            job = service.enqueue(FARMER, f"{FARMER}/leaf-scans/a.jpg", "scan_deleted")
            await session.commit()

            await service.process([job.id])
            remaining = await session.scalar(select(func.count()).select_from(ObjectDeletionJob))
            persisted = await session.get(ObjectDeletionJob, job.id)
            storage.fail = False
            attempted = await service.retry_owner(FARMER)
            final = await session.scalar(select(func.count()).select_from(ObjectDeletionJob))
    finally:
        await engine.dispose()

    assert remaining == 1
    assert persisted is not None and persisted.attempts == 1
    assert attempted == 1
    assert final == 0


@pytest.mark.asyncio
async def test_background_worker_automatically_reconciles_due_jobs() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    storage = FlakyStorage()
    storage.fail = False

    class TestDatabase:
        def session(self) -> AbstractAsyncContextManager[AsyncSession]:
            return sessions()

        async def ping(self) -> None:
            return None

        async def dispose(self) -> None:
            return None

    try:
        async with sessions() as session:
            session.add(
                FarmerProfile(
                    id=FARMER,
                    cognito_sub="worker",
                    cognito_username="worker@example.com",
                    email="worker@example.com",
                )
            )
            service = ObjectCleanupService(session, storage)
            service.enqueue(FARMER, f"{FARMER}/leaf-scans/b.jpg", "scan_deleted")
            await session.commit()

        worker = ObjectCleanupWorker(
            settings=Settings(
                _env_file=None,
                object_cleanup_interval_seconds=1,
            ),
            database=TestDatabase(),
            storage=storage,
        )
        await worker.start()
        await asyncio.wait_for(storage.deleted.wait(), timeout=5)
        for _ in range(100):
            async with sessions() as session:
                count = await session.scalar(select(func.count()).select_from(ObjectDeletionJob))
            if count == 0:
                break
            await asyncio.sleep(0.01)
        await worker.stop()
    finally:
        await engine.dispose()

    assert count == 0
