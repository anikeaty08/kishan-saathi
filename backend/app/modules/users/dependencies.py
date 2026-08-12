"""Request-scoped farmer-profile dependency assembly."""

from typing import Annotated
from uuid import UUID

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_auth_context, get_auth_provider, get_db_session
from app.core.security import AuthContext
from app.integrations.auth.provider import AuthProvider
from app.modules.users.repository import SqlAlchemyUserRepository
from app.modules.users.service import UserService, UserServicePort


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


async def get_current_farmer_id(
    context: Annotated[AuthContext, Depends(get_auth_context)],
    service: Annotated[UserServicePort, Depends(get_user_service)],
) -> UUID:
    """Resolve the local owner ID for the verified Cognito subject."""

    return (await service.get_profile(context)).id
