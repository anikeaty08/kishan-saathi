"""Farmer-profile persistence contract and SQLAlchemy adapter boundary."""

from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import ExternalIdentity
from app.modules.users.models import FarmerProfile


class UserRepositoryPort(Protocol):
    """Persistence operations required by farmer-profile use cases."""

    async def get_by_subject(self, subject: str) -> FarmerProfile | None: ...

    def add(self, identity: ExternalIdentity) -> FarmerProfile: ...


class SqlAlchemyUserRepository:
    """SQLAlchemy implementation of farmer-profile persistence."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_subject(self, subject: str) -> FarmerProfile | None:
        result = await self._session.execute(
            select(FarmerProfile).where(FarmerProfile.cognito_sub == subject)
        )
        return result.scalar_one_or_none()

    def add(self, identity: ExternalIdentity) -> FarmerProfile:
        profile = FarmerProfile(
            cognito_sub=identity.subject,
            cognito_username=identity.username,
            email=identity.email,
            email_verified=identity.email_verified,
        )
        self._session.add(profile)
        return profile
