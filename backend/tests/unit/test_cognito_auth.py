"""Unit tests for Cognito JWT and identity-provider boundaries."""

from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.auth.cognito import CognitoAuthProvider

PRIVATE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
KID = "test-key"
POOL_ID = "ap-south-1_testpool"
CLIENT_ID = "test-client"


def _jwk() -> dict[str, Any]:
    value = RSAAlgorithm.to_jwk(PRIVATE_KEY.public_key(), as_dict=True)
    return {**value, "kid": KID, "alg": "RS256", "use": "sig"}


def _token(*, client_id: str = CLIENT_ID, token_use: str = "access") -> str:
    now = datetime.now(tz=UTC)
    return jwt.encode(
        {
            "sub": "farmer-sub",
            "username": "farmer@example.com",
            "iss": f"https://cognito-idp.ap-south-1.amazonaws.com/{POOL_ID}",
            "client_id": client_id,
            "token_use": token_use,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(minutes=5)).timestamp()),
        },
        PRIVATE_KEY,
        algorithm="RS256",
        headers={"kid": KID},
    )


def _settings() -> Settings:
    return Settings(
        _env_file=None,
        app_env="test",
        cognito_user_pool_id=POOL_ID,
        cognito_app_client_id=CLIENT_ID,
    )


@pytest.mark.asyncio
async def test_verifies_access_token_and_caches_jwks() -> None:
    jwks_requests = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal jwks_requests
        assert request.url.path.endswith("/.well-known/jwks.json")
        jwks_requests += 1
        return httpx.Response(200, json={"keys": [_jwk()]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider = CognitoAuthProvider(_settings(), http_client=client)
        first = await provider.verify_access_token(_token())
        second = await provider.verify_access_token(_token())

    assert first.subject == "farmer-sub"
    assert first.username == "farmer@example.com"
    assert second.subject == first.subject
    assert jwks_requests == 1


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("client_id", "token_use"),
    [("wrong-client", "access"), (CLIENT_ID, "id")],
)
async def test_rejects_wrong_client_or_token_use(client_id: str, token_use: str) -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"keys": [_jwk()]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider = CognitoAuthProvider(_settings(), http_client=client)
        with pytest.raises(ApplicationError) as raised:
            await provider.verify_access_token(_token(client_id=client_id, token_use=token_use))

    assert raised.value.code == "AUTH_TOKEN_INVALID"
    assert raised.value.status_code == 401


@pytest.mark.asyncio
async def test_get_identity_reads_email_from_cognito_get_user() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-amz-target"] == "AWSCognitoIdentityProviderService.GetUser"
        return httpx.Response(
            200,
            json={
                "Username": "farmer@example.com",
                "UserAttributes": [
                    {"Name": "sub", "Value": "farmer-sub"},
                    {"Name": "email", "Value": "farmer@example.com"},
                    {"Name": "email_verified", "Value": "true"},
                    {"Name": "name", "Value": "Nikhil Kumar"},
                ],
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider = CognitoAuthProvider(_settings(), http_client=client)
        identity = await provider.get_identity("access-token")

    assert identity.subject == "farmer-sub"
    assert identity.email == "farmer@example.com"
    assert identity.email_verified is True
    assert identity.name == "Nikhil Kumar"


@pytest.mark.asyncio
async def test_jwks_failure_is_reported_as_provider_unavailable() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(503)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider = CognitoAuthProvider(_settings(), http_client=client)
        with pytest.raises(ApplicationError) as raised:
            await provider.verify_access_token(_token())

    assert raised.value.code == "AUTH_PROVIDER_UNAVAILABLE"
    assert raised.value.status_code == 503
