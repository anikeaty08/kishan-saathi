"""Shared FastAPI dependency declarations."""

from collections.abc import AsyncIterator
from typing import Annotated, cast

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.core.rate_limits import AuthRateLimiter, PaidOperationRateLimiter
from app.core.security import AuthContext
from app.database.session import DatabasePort
from app.integrations.audio.provider import AudioProvider
from app.integrations.auth.provider import AuthProvider
from app.integrations.geocoding.provider import GeocodingProvider
from app.integrations.inference.provider import LeafInferenceProvider
from app.integrations.llm.provider import LLMProvider
from app.integrations.memory.provider import MemoryProvider
from app.integrations.progression.provider import ProgressionProvider
from app.integrations.storage.provider import ObjectStorageProvider
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider

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


def get_object_storage(request: Request) -> ObjectStorageProvider:
    """Resolve private object storage selected during startup."""

    return cast(ObjectStorageProvider, request.app.state.object_storage)


def get_leaf_inference_provider(request: Request) -> LeafInferenceProvider:
    """Resolve the leaf model provider selected during startup."""

    return cast(LeafInferenceProvider, request.app.state.leaf_inference_provider)


def get_llm_provider(request: Request) -> LLMProvider:
    return cast(LLMProvider, request.app.state.llm_provider)


def get_memory_provider(request: Request) -> MemoryProvider:
    return cast(MemoryProvider, request.app.state.memory_provider)


def get_progression_provider(request: Request) -> ProgressionProvider:
    return cast(ProgressionProvider, request.app.state.progression_provider)


def get_audio_provider(request: Request) -> AudioProvider:
    return cast(AudioProvider, request.app.state.audio_provider)


def get_paid_operation_rate_limiter(request: Request) -> PaidOperationRateLimiter:
    return cast(PaidOperationRateLimiter, request.app.state.paid_operation_rate_limiter)


def get_auth_rate_limiter(request: Request) -> AuthRateLimiter:
    return cast(AuthRateLimiter, request.app.state.auth_rate_limiter)


def get_current_weather_provider(request: Request) -> CurrentWeatherProvider:
    return cast(CurrentWeatherProvider, request.app.state.current_weather_provider)


def get_forecast_weather_provider(request: Request) -> ForecastWeatherProvider:
    return cast(ForecastWeatherProvider, request.app.state.forecast_weather_provider)


def get_geocoding_provider(request: Request) -> GeocodingProvider:
    return cast(GeocodingProvider, request.app.state.geocoding_provider)


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
