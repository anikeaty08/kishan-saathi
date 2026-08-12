"""Contract tests for public health endpoints."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Self

import pytest
from asgi_lifespan import LifespanManager
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.main import create_app


class FakeDatabase:
    """Controllable database probe for API contract tests."""

    def __init__(self, *, available: bool = True) -> None:
        self.available = available
        self.ping_count = 0
        self.disposed = False

    async def ping(self) -> None:
        self.ping_count += 1
        if not self.available:
            raise ConnectionError("test database unavailable")

    async def dispose(self) -> None:
        self.disposed = True

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        raise AssertionError("Health contract tests must not open a database session")
        yield  # pragma: no cover

    def fail(self) -> Self:
        self.available = False
        return self


@pytest.mark.asyncio
async def test_liveness_does_not_contact_database() -> None:
    database = FakeDatabase()
    app = create_app(_test_settings(), database)

    async with LifespanManager(app):
        response = await _get(app, "/health/live", headers={"X-Request-ID": "health-test"})

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == "health-test"
    assert response.json() == {
        "status": "ok",
        "service": "Kishan Saathi Test API",
        "version": "test",
        "checks": {},
    }
    assert database.ping_count == 0
    assert database.disposed is True


@pytest.mark.asyncio
async def test_readiness_reports_available_database() -> None:
    database = FakeDatabase()
    app = create_app(_test_settings(), database)

    async with LifespanManager(app):
        response = await _get(app, "/health/ready")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["checks"] == {
        "database": {"status": "up"},
        "authentication": {"status": "down"},
        "llm": {"status": "down"},
        "memory": {"status": "down"},
        "current_weather": {"status": "down"},
        "leaf_inference": {"status": "down"},
    }
    assert database.ping_count == 1


@pytest.mark.asyncio
async def test_readiness_is_safe_when_database_is_unavailable() -> None:
    database = FakeDatabase().fail()
    app = create_app(_test_settings(), database)

    async with LifespanManager(app):
        response = await _get(app, "/health/ready")

    assert response.status_code == 503
    assert response.json()["status"] == "not_ready"
    assert response.json()["checks"]["database"] == {"status": "down"}
    assert "test database unavailable" not in response.text


@pytest.mark.asyncio
async def test_unknown_route_uses_structured_error_contract() -> None:
    app = create_app(_test_settings(), FakeDatabase())

    async with LifespanManager(app):
        response = await _get(app, "/does-not-exist")

    body = response.json()
    assert response.status_code == 404
    assert body["error"]["code"] == "RESOURCE_NOT_FOUND"
    assert body["error"]["request_id"] == response.headers["X-Request-ID"]


@pytest.mark.asyncio
async def test_validation_failure_uses_structured_error_contract() -> None:
    app = create_app(_test_settings(), FakeDatabase())

    @app.get("/requires-number")
    async def requires_number(value: int) -> dict[str, int]:
        return {"value": value}

    async with LifespanManager(app):
        response = await _get(app, "/requires-number?value=not-a-number")

    body = response.json()
    assert response.status_code == 422
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["error"]["details"]
    assert body["error"]["request_id"] == response.headers["X-Request-ID"]


@pytest.mark.asyncio
async def test_unexpected_failure_does_not_leak_internal_details() -> None:
    app = create_app(_test_settings(), FakeDatabase())

    @app.get("/fails")
    async def fails() -> None:
        raise RuntimeError("private failure detail")

    async with LifespanManager(app):
        response = await _get(app, "/fails")

    body = response.json()
    assert response.status_code == 500
    assert body["error"]["code"] == "INTERNAL_ERROR"
    assert "private failure detail" not in response.text
    assert body["error"]["request_id"] == response.headers["X-Request-ID"]


async def _get(
    app: FastAPI,
    path: str,
    *,
    headers: dict[str, str] | None = None,
) -> Response:
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.get(path, headers=headers)


def _test_settings() -> Settings:
    return Settings(
        _env_file=None,
        app_env="test",
        app_name="Kishan Saathi Test API",
        app_version="test",
        log_level="CRITICAL",
        database_url="postgresql+asyncpg://unused:unused@localhost:5432/unused",
    )
