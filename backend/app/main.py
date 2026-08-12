"""FastAPI application factory and process entry point."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI

from app.api.router import api_router, versioned_api_router
from app.core.config import Settings, get_settings
from app.core.container import build_auth_provider
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging, request_context_middleware
from app.database.session import Database, DatabasePort
from app.integrations.auth.provider import AuthProvider


def create_app(
    settings: Settings | None = None,
    database: DatabasePort | None = None,
    auth_provider: AuthProvider | None = None,
) -> FastAPI:
    """Build an application with explicit, replaceable process dependencies."""

    resolved_settings = settings or get_settings()
    configure_logging(resolved_settings.log_level)
    resolved_database = database or Database(resolved_settings)
    resolved_auth_provider = auth_provider or build_auth_provider(resolved_settings)

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        logger = structlog.get_logger("lifecycle")
        logger.info("application.started", environment=resolved_settings.app_env)
        try:
            yield
        finally:
            await application.state.auth_provider.close()
            await application.state.database.dispose()
            logger.info("application.stopped")

    application = FastAPI(
        title=resolved_settings.app_name,
        version=resolved_settings.app_version,
        debug=resolved_settings.debug,
        lifespan=lifespan,
    )
    application.state.settings = resolved_settings
    application.state.database = resolved_database
    application.state.auth_provider = resolved_auth_provider
    application.middleware("http")(request_context_middleware)
    register_error_handlers(application)
    application.include_router(api_router)
    application.include_router(
        versioned_api_router,
        prefix=resolved_settings.api_v1_prefix,
    )
    return application


app = create_app()
