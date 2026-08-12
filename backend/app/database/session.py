"""Asynchronous SQLAlchemy engine and session lifecycle."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Protocol

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import Settings


class DatabasePort(Protocol):
    """Small database lifecycle contract required by the application."""

    async def ping(self) -> None: ...

    async def dispose(self) -> None: ...

    def session(self) -> AbstractAsyncContextManager[AsyncSession]: ...


class Database:
    """Own the SQLAlchemy engine and asynchronous session factory."""

    def __init__(self, settings: Settings) -> None:
        self._timeout = settings.database_connect_timeout_seconds
        self._engine: AsyncEngine = create_async_engine(
            settings.database_url,
            echo=settings.debug,
            pool_pre_ping=True,
            pool_recycle=1800,
        )
        self._sessions = async_sessionmaker(
            bind=self._engine,
            class_=AsyncSession,
            expire_on_commit=False,
            autoflush=False,
        )

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        """Yield a session without hiding transaction ownership from services."""

        async with self._sessions() as session:
            try:
                yield session
            except Exception:
                await session.rollback()
                raise

    async def ping(self) -> None:
        """Verify that PostgreSQL accepts a bounded trivial query."""

        async with asyncio.timeout(self._timeout):
            async with self._engine.connect() as connection:
                await connection.execute(text("SELECT 1"))

    async def dispose(self) -> None:
        """Release all pooled database connections during shutdown."""

        await self._engine.dispose()
