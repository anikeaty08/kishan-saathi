"""Shared FastAPI dependency declarations."""

from collections.abc import AsyncIterator
from typing import Annotated, cast

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.core.security import AuthContext
from app.database.session import DatabasePort
from app.integrations.auth.provider import AuthProvider

bearer_scheme = HTTPBearer(auto_error=False)


def get_app_settings(request: Request) -> Settings:
    """Resolve the settings instance owned by this FastAPI application."""

    return cast(Settings, request.app.state.settings)


def get_database(request: Request) -> DatabasePort:
    """Resolve the database adapter owned by this FastAPI application."""

    return cast(DatabasePort, request.app.state.database)


def get_auth_provider(request: Request) -> AuthProvider:
    """Resolve the authentication adapter selected during startup."""

    return cast(AuthProvider, request.app.state.auth_provider)


async def get_auth_context(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
    provider: Annotated[AuthProvider, Depends(get_auth_provider)],
) -> AuthContext:
    """Validate the bearer access token and return its trusted identity."""

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApplicationError(code="AUTH_TOKEN_REQUIRED", status_code=401)
    principal = await provider.verify_access_token(credentials.credentials)
    return AuthContext(principal=principal, access_token=credentials.credentials)


async def get_db_session(
    database: Annotated[DatabasePort, Depends(get_database)],
) -> AsyncIterator[AsyncSession]:
    """Provide one request-scoped SQLAlchemy session."""

    async with database.session() as session:
        yield session
