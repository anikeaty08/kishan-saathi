"""Authenticated farmer-profile HTTP endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import (
    get_auth_context,
    get_auth_provider,
    get_db_session,
)
from app.core.security import AuthContext
from app.integrations.auth.provider import AuthProvider
from app.modules.users.repository import SqlAlchemyUserRepository
from app.modules.users.schemas import FarmerProfileResponse, FarmerProfileUpdate
from app.modules.users.service import UserService, UserServicePort

router = APIRouter(prefix="/me", tags=["farmer-profile"])


def get_user_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
    auth_provider: Annotated[AuthProvider, Depends(get_auth_provider)],
) -> UserServicePort:
    """Build a request-scoped farmer-profile service."""

    return UserService(
        session=session,
        repository=SqlAlchemyUserRepository(session),
        auth_provider=auth_provider,
    )


@router.get("", response_model=FarmerProfileResponse)
async def get_my_profile(
    context: Annotated[AuthContext, Depends(get_auth_context)],
    service: Annotated[UserServicePort, Depends(get_user_service)],
) -> FarmerProfileResponse:
    """Get or provision the authenticated farmer's local profile."""

    return await service.get_profile(context)


@router.patch("", response_model=FarmerProfileResponse)
async def update_my_profile(
    changes: FarmerProfileUpdate,
    context: Annotated[AuthContext, Depends(get_auth_context)],
    service: Annotated[UserServicePort, Depends(get_user_service)],
) -> FarmerProfileResponse:
    """Update editable onboarding and profile preferences."""

    return await service.update_profile(context, changes)
