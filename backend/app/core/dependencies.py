"""Shared FastAPI dependency declarations."""

from typing import cast

from fastapi import Request

from app.core.config import Settings
from app.database.session import DatabasePort


def get_app_settings(request: Request) -> Settings:
    """Resolve the settings instance owned by this FastAPI application."""

    return cast(Settings, request.app.state.settings)


def get_database(request: Request) -> DatabasePort:
    """Resolve the database adapter owned by this FastAPI application."""

    return cast(DatabasePort, request.app.state.database)
