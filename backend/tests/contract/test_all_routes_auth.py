"""Route-derived HTTP checks for the complete public API surface.

These tests intentionally derive requests from OpenAPI so a newly registered
route cannot silently miss the authentication-boundary audit.
"""

import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.main import create_app
from app.modules.reports.dependencies import get_report_service

_HTTP_METHODS = {"get", "post", "put", "patch", "delete"}
_RESOURCE_ID = str(UUID(int=1))


class _FakeDatabase:
    """Healthy probe that fails if an audited request unexpectedly reaches SQL."""

    async def ping(self) -> None:
        return None

    async def dispose(self) -> None:
        return None

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        raise AssertionError("authentication-boundary request unexpectedly opened SQL")
        yield  # pragma: no cover


class _MissingPublicReportService:
    async def public(self, report_id: UUID, token: str) -> None:
        del report_id, token
        raise ApplicationError(code="RESOURCE_NOT_FOUND", status_code=404)

    async def public_image(self, report_id: UUID, token: str, image_id: UUID) -> None:
        del report_id, token, image_id
        raise ApplicationError(code="RESOURCE_NOT_FOUND", status_code=404)


def _app() -> Any:
    settings = Settings(
        _env_file=None,
        app_env="test",
        log_level="CRITICAL",
        database_url="postgresql+asyncpg://unused:unused@localhost:5432/unused",
        leaf_inference_backend="disabled",
    )
    application = create_app(settings=settings, database=_FakeDatabase())
    application.dependency_overrides[get_report_service] = _MissingPublicReportService
    return application


def _operations(application: Any) -> list[tuple[str, str]]:
    operations: list[tuple[str, str]] = []
    for path, path_item in application.openapi()["paths"].items():
        for method in _HTTP_METHODS.intersection(path_item):
            operations.append((method.upper(), path))
    return sorted(operations)


def _concrete_path(path: str) -> str:
    return re.sub(r"\{[^}]+\}", _RESOURCE_ID, path)


@pytest.mark.asyncio
async def test_every_protected_operation_fails_closed_without_bearer_token() -> None:
    application = _app()
    protected = [
        operation
        for operation in _operations(application)
        if operation[1].startswith("/api/v1/")
        and not operation[1].startswith("/api/v1/shared/")
        and not operation[1].startswith("/api/v1/auth/")
    ]

    transport = ASGITransport(app=application, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for method, path in protected:
            response = await client.request(method, _concrete_path(path))
            assert response.status_code == 401, (method, path, response.text)
            assert response.json()["error"]["code"] == "AUTH_TOKEN_REQUIRED", (method, path)

    assert len(protected) == 76


@pytest.mark.asyncio
async def test_every_public_operation_is_reachable_without_bearer_authentication() -> None:
    application = _app()
    public = [
        operation
        for operation in _operations(application)
        if operation[1].startswith("/health/")
        or operation[1].startswith("/api/v1/shared/")
    ]
    headers = {"X-Report-Token": "x" * 32}

    transport = ASGITransport(app=application, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for method, path in public:
            response = await client.request(method, _concrete_path(path), headers=headers)
            if path.startswith("/health/"):
                assert response.status_code == 200, (method, path, response.text)
                assert response.json()["status"] == "ok"
            else:
                assert response.status_code == 404, (method, path, response.text)
                assert response.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    assert len(public) == 4
    auth_operations = [
        operation
        for operation in _operations(application)
        if operation[1].startswith("/api/v1/auth/")
    ]
    assert len(auth_operations) == 7
    assert len(_operations(application)) == 87
