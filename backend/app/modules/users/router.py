"""Authenticated farmer-profile HTTP endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.dependencies import get_auth_context
from app.core.security import AuthContext
from app.modules.users.dependencies import get_user_service
from app.modules.users.schemas import FarmerProfileResponse, FarmerProfileUpdate
from app.modules.users.service import UserServicePort

router = APIRouter(prefix="/me", tags=["farmer-profile"])


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
