"""Unit tests for validated application configuration."""

import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_settings_reject_unsupported_environment() -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, app_env="unknown")


def test_settings_reject_non_positive_database_timeout() -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, database_connect_timeout_seconds=0)
