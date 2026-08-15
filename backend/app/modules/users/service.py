"""Farmer-profile application use cases."""

from typing import Protocol

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ApplicationError
from app.core.security import AuthContext
from app.integrations.auth.provider import AuthProvider
from app.modules.users.models import FarmerProfile
from app.modules.users.repository import UserRepositoryPort
from app.modules.users.schemas import (
    AreaUnit,
    FarmerProfileResponse,
    FarmerProfileUpdate,
    SupportedLanguage,
)


class UserServicePort(Protocol):
    """Use cases exposed to the farmer-profile transport layer."""

    async def get_profile(self, context: AuthContext) -> FarmerProfileResponse: ...

    async def update_profile(
        self,
        context: AuthContext,
        changes: FarmerProfileUpdate,
    ) -> FarmerProfileResponse: ...


class UserService:
    """Provision and update the authenticated farmer's local profile."""

    def __init__(
        self,
        session: AsyncSession,
        repository: UserRepositoryPort,
        auth_provider: AuthProvider,
    ) -> None:
        self._session = session
        self._repository = repository
        self._auth_provider = auth_provider

    async def get_profile(self, context: AuthContext) -> FarmerProfileResponse:
        profile = await self._get_or_create(context)
        return self._response(profile)

    async def update_profile(
        self,
        context: AuthContext,
        changes: FarmerProfileUpdate,
    ) -> FarmerProfileResponse:
        profile = await self._get_or_create(context)
        for field in changes.model_fields_set:
            value = getattr(changes, field)
            if isinstance(value, SupportedLanguage | AreaUnit):
                value = value.value
            setattr(profile, field, value)
        await self._session.commit()
        await self._session.refresh(profile)
        return self._response(profile)

    async def _get_or_create(self, context: AuthContext) -> FarmerProfile:
        subject = context.principal.subject
        profile = await self._repository.get_by_subject(subject)
        if profile is not None:
            return profile

        identity = await self._auth_provider.get_identity(context.access_token)
        if identity.subject != subject:
            raise ApplicationError(code="AUTH_IDENTITY_MISMATCH", status_code=401)

        profile = self._repository.add(identity)
        try:
            await self._session.commit()
        except IntegrityError:
            await self._session.rollback()
            profile = await self._repository.get_by_subject(subject)
            if profile is None:
                raise
        await self._session.refresh(profile)
        return profile

    @staticmethod
    def _response(profile: FarmerProfile) -> FarmerProfileResponse:
        return FarmerProfileResponse(
            id=profile.id,
            email=profile.email,
            email_verified=profile.email_verified,
            name=profile.name,
            preferred_language=(
                SupportedLanguage(profile.preferred_language)
                if profile.preferred_language
                else None
            ),
            area_unit=AreaUnit(profile.area_unit),
            notifications_enabled=profile.notifications_enabled,
            onboarding_complete=bool(profile.name and profile.preferred_language),
            created_at=profile.created_at,
            updated_at=profile.updated_at,
        )
