"""Contract tests for the FastAPI-mediated Cognito account lifecycle."""

from typing import Any

import pytest
from asgi_lifespan import LifespanManager
from httpx import ASGITransport, AsyncClient

from app.core.dependencies import get_auth_rate_limiter
from app.core.errors import ApplicationError
from app.core.rate_limits import AuthRateLimiter
from app.integrations.auth.accounts import AuthTokens
from app.main import create_app
from tests.contract.test_health_api import FakeDatabase, _test_settings


class FakeAccountAuthProvider:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[str, ...]]] = []

    async def sign_up(self, name: str, email: str, password: str) -> bool:
        self.calls.append(("sign_up", (name, email, password)))
        return False

    async def confirm_sign_up(self, email: str, code: str) -> None:
        self.calls.append(("confirm", (email, code)))

    async def resend_confirmation(self, email: str) -> None:
        self.calls.append(("resend", (email,)))

    async def sign_in(self, email: str, password: str) -> AuthTokens:
        self.calls.append(("sign_in", (email, password)))
        if password == "incorrect-password":
            raise ApplicationError(code="AUTH_INCORRECT_CREDENTIALS", status_code=400)
        return AuthTokens("access", "refresh", "id", 3600)

    async def refresh(self, refresh_token: str) -> AuthTokens:
        self.calls.append(("refresh", (refresh_token,)))
        return AuthTokens("new-access", refresh_token, "new-id", 3600)

    async def request_password_reset(self, email: str) -> None:
        self.calls.append(("password_reset", (email,)))

    async def confirm_password_reset(
        self, email: str, code: str, new_password: str
    ) -> None:
        self.calls.append(("password_reset_confirm", (email, code, new_password)))

    async def close(self) -> None:
        return None


@pytest.fixture
async def client_and_provider() -> Any:
    settings = _test_settings()
    provider = FakeAccountAuthProvider()
    app = create_app(
        settings=settings,
        database=FakeDatabase(),
        account_auth_provider=provider,
    )
    app.dependency_overrides[get_auth_rate_limiter] = lambda: AuthRateLimiter(settings)
    async with LifespanManager(app), AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        yield client, provider


async def test_sign_up_confirmation_resend_and_sign_in_are_public_and_no_store(
    client_and_provider: tuple[AsyncClient, FakeAccountAuthProvider],
) -> None:
    client, provider = client_and_provider
    sign_up = await client.post(
        "/api/v1/auth/sign-up",
        json={
            "name": "  Nikhil   Kumar  ",
            "email": "Farmer@Example.com",
            "password": "valid-password",
        },
    )
    assert sign_up.status_code == 201
    assert sign_up.json() == {"confirmed": False}
    assert sign_up.headers["cache-control"] == "private, no-store"

    confirm = await client.post(
        "/api/v1/auth/confirm",
        json={"email": "farmer@example.com", "code": "123456"},
    )
    resend = await client.post(
        "/api/v1/auth/resend", json={"email": "farmer@example.com"}
    )
    sign_in = await client.post(
        "/api/v1/auth/sign-in",
        json={"email": "farmer@example.com", "password": "valid-password"},
    )

    assert confirm.status_code == 204
    assert resend.status_code == 204
    assert sign_in.status_code == 200
    assert sign_in.json()["access_token"] == "access"
    responses = [confirm, resend, sign_in]
    assert all(
        response.headers["cache-control"] == "private, no-store"
        for response in responses
    )
    assert provider.calls[0] == (
        "sign_up",
        ("Nikhil Kumar", "farmer@example.com", "valid-password"),
    )


async def test_auth_errors_are_typed_and_passwords_are_not_echoed(
    client_and_provider: tuple[AsyncClient, FakeAccountAuthProvider],
) -> None:
    client, _ = client_and_provider
    response = await client.post(
        "/api/v1/auth/sign-in",
        json={"email": "farmer@example.com", "password": "incorrect-password"},
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "AUTH_INCORRECT_CREDENTIALS"
    assert "incorrect-password" not in response.text


async def test_sign_up_rejects_a_blank_farmer_name_before_cognito(
    client_and_provider: tuple[AsyncClient, FakeAccountAuthProvider],
) -> None:
    client, provider = client_and_provider
    response = await client.post(
        "/api/v1/auth/sign-up",
        json={
            "name": "   ",
            "email": "farmer@example.com",
            "password": "valid-password",
        },
    )

    assert response.status_code == 422
    assert provider.calls == []
