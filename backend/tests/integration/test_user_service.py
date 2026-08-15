"""Integration tests for farmer-profile persistence and service behavior."""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.security import AuthContext, AuthenticatedPrincipal, ExternalIdentity
from app.database.base import Base
from app.integrations.auth.provider import AuthProvider
from app.modules.users.repository import SqlAlchemyUserRepository
from app.modules.users.schemas import FarmerProfileUpdate, SupportedLanguage
from app.modules.users.service import UserService


class FakeAuthProvider(AuthProvider):
    """Return one canonical Cognito identity and count provider lookups."""

    def __init__(self) -> None:
        self.identity_requests = 0

    async def verify_access_token(self, access_token: str) -> AuthenticatedPrincipal:
        raise AssertionError(access_token)

    async def get_identity(self, access_token: str) -> ExternalIdentity:
        assert access_token == "valid-access-token"
        self.identity_requests += 1
        return ExternalIdentity(
            subject="farmer-sub",
            username="farmer@example.com",
            email="farmer@example.com",
            email_verified=True,
            name="Nikhil",
        )

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_profile_is_provisioned_once_and_updated() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    sessions = async_sessionmaker(engine, expire_on_commit=False)
    provider = FakeAuthProvider()
    context = AuthContext(
        principal=AuthenticatedPrincipal(
            subject="farmer-sub",
            username="farmer@example.com",
            expires_at=datetime.now(tz=UTC) + timedelta(minutes=5),
        ),
        access_token="valid-access-token",
    )

    try:
        async with sessions() as session:
            service = UserService(session, SqlAlchemyUserRepository(session), provider)
            initial = await service.get_profile(context)
            updated = await service.update_profile(
                context,
                FarmerProfileUpdate(
                    name="Nikhil",
                    preferred_language=SupportedLanguage.HINDI,
                    notifications_enabled=True,
                ),
            )
            loaded_again = await service.get_profile(context)
    finally:
        await engine.dispose()

    assert initial.email == "farmer@example.com"
    assert initial.name == "Nikhil"
    assert initial.onboarding_complete is False
    assert updated.name == "Nikhil"
    assert updated.preferred_language is SupportedLanguage.HINDI
    assert updated.notifications_enabled is True
    assert updated.onboarding_complete is True
    assert loaded_again.id == initial.id
    assert provider.identity_requests == 1
