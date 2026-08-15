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


def test_chat_turn_timeout_must_be_shorter_than_lease() -> None:
    with pytest.raises(ValidationError, match="CHAT_TURN_TIMEOUT_MUST_BE_SHORTER_THAN_LEASE"):
        Settings(
            _env_file=None,
            chat_turn_processing_timeout_seconds=180,
            chat_turn_lease_seconds=180,
        )
