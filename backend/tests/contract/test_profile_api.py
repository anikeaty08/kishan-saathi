"""API contract tests for authenticated farmer-profile endpoints."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from asgi_lifespan import LifespanManager
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.security import AuthContext, AuthenticatedPrincipal, ExternalIdentity
from app.integrations.auth.provider import AuthProvider
from app.main import create_app
from app.modules.users.dependencies import get_user_service
from app.modules.users.schemas import (
    AreaUnit,
    FarmerProfileResponse,
    FarmerProfileUpdate,
)
from app.modules.users.service import UserServicePort

NOW = datetime(2026, 8, 12, tzinfo=UTC)


class FakeDatabase:
    async def ping(self) -> None:
        return None

    async def dispose(self) -> None:
        return None

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        raise AssertionError("The overridden profile service must not open a database session")
        yield  # pragma: no cover


class FakeAuthProvider(AuthProvider):
    def __init__(self) -> None:
        self.closed = False

    async def verify_access_token(self, access_token: str) -> AuthenticatedPrincipal:
        if access_token != "valid-token":
            raise AssertionError(access_token)
        return AuthenticatedPrincipal(
            subject="farmer-sub",
            username="farmer@example.com",
            expires_at=NOW + timedelta(minutes=5),
        )

    async def get_identity(self, access_token: str) -> ExternalIdentity:
        raise AssertionError(access_token)

    async def close(self) -> None:
        self.closed = True


class FakeUserService(UserServicePort):
    def __init__(self) -> None:
        self.profile = FarmerProfileResponse(
            id=UUID("00000000-0000-0000-0000-000000000001"),
            email="farmer@example.com",
            email_verified=True,
            name=None,
            preferred_language=None,
            area_unit=AreaUnit.ACRE,
            notifications_enabled=False,
            onboarding_complete=False,
            created_at=NOW,
            updated_at=NOW,
        )

    async def get_profile(self, context: AuthContext) -> FarmerProfileResponse:
        assert context.principal.subject == "farmer-sub"
        return self.profile

    async def update_profile(
        self,
        context: AuthContext,
        changes: FarmerProfileUpdate,
    ) -> FarmerProfileResponse:
        assert context.principal.subject == "farmer-sub"
        update = {
            field: getattr(changes, field) for field in changes.model_fields_set
        }
        name = update.get("name", self.profile.name)
        language = update.get("preferred_language", self.profile.preferred_language)
        update["onboarding_complete"] = bool(name and language)
        self.profile = self.profile.model_copy(update=update)
        return self.profile


@pytest.mark.asyncio
async def test_profile_requires_access_token() -> None:
    app, _provider = _app()
    async with LifespanManager(app):
        response = await _request(app, "GET", "/api/v1/me")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_TOKEN_REQUIRED"
    assert "message" not in response.json()["error"]


@pytest.mark.asyncio
async def test_get_profile_uses_verified_principal() -> None:
    app, provider = _app()
    async with LifespanManager(app):
        response = await _request(app, "GET", "/api/v1/me", token="valid-token")

    assert response.status_code == 200
    assert response.json()["email"] == "farmer@example.com"
    assert response.json()["onboarding_complete"] is False
    assert provider.closed is True


@pytest.mark.asyncio
async def test_patch_profile_validates_language_and_updates_onboarding() -> None:
    app, _provider = _app()
    async with LifespanManager(app):
        invalid = await _request(
            app,
            "PATCH",
            "/api/v1/me",
            token="valid-token",
            json={"name": "Nikhil", "preferred_language": "xx"},
        )
        valid = await _request(
            app,
            "PATCH",
            "/api/v1/me",
            token="valid-token",
            json={"name": "Nikhil", "preferred_language": "hi"},
        )

    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "VALIDATION_ERROR"
    assert valid.status_code == 200
    assert valid.json()["name"] == "Nikhil"
    assert valid.json()["preferred_language"] == "hi"
    assert valid.json()["onboarding_complete"] is True


@pytest.mark.asyncio
async def test_patch_profile_settings_are_partial_and_do_not_erase_identity() -> None:
    app, _provider = _app()
    async with LifespanManager(app):
        await _request(
            app,
            "PATCH",
            "/api/v1/me",
            token="valid-token",
            json={"name": "Nikhil", "preferred_language": "hi"},
        )
        settings = await _request(
            app,
            "PATCH",
            "/api/v1/me",
            token="valid-token",
            json={"area_unit": "hectare", "notifications_enabled": True},
        )

    assert settings.status_code == 200
    assert settings.json()["name"] == "Nikhil"
    assert settings.json()["preferred_language"] == "hi"
    assert settings.json()["area_unit"] == "hectare"
    assert settings.json()["notifications_enabled"] is True
    assert settings.json()["onboarding_complete"] is True


def _app() -> tuple[FastAPI, FakeAuthProvider]:
    provider = FakeAuthProvider()
    service = FakeUserService()
    settings = Settings(
        _env_file=None,
        app_env="test",
        log_level="CRITICAL",
        database_url="postgresql+asyncpg://unused:unused@localhost:5432/unused",
    )
    app = create_app(settings, FakeDatabase(), provider)
    app.dependency_overrides[get_user_service] = lambda: service
    return app, provider


async def _request(
    app: FastAPI,
    method: str,
    path: str,
    *,
    token: str | None = None,
    json: dict[str, object] | None = None,
) -> Response:
    headers = {"Authorization": f"Bearer {token}"} if token else None
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.request(method, path, headers=headers, json=json)
