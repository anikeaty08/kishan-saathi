"""Pydantic Settings configuration boundary."""

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Validated process configuration loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_env: Literal["development", "test", "staging", "production"] = "development"
    app_name: str = "Kishan Saathi API"
    app_version: str = "0.1.0"
    api_v1_prefix: str = "/api/v1"
    log_level: str = "INFO"
    debug: bool = False

    database_url: str = "postgresql+asyncpg://krishisathi:krishisathi@localhost:5432/krishisathi"
    database_connect_timeout_seconds: float = Field(default=3.0, gt=0, le=30)

    aws_region: str = "ap-south-1"
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""
    cognito_jwks_cache_seconds: int = Field(default=3600, ge=60, le=86400)
    external_request_timeout_seconds: float = Field(default=5.0, gt=0, le=30)

    openai_api_key: str = ""
    openai_primary_model: str = "gpt-5"
    openai_light_model: str = "gpt-5-mini"
    mem0_api_key: str = ""

    local_storage_path: str = "./storage"
    max_image_bytes: int = Field(default=10 * 1024 * 1024, ge=1024, le=50 * 1024 * 1024)
    max_diagnosis_upload_bytes: int = Field(
        default=50 * 1024 * 1024,
        ge=1024,
        le=250 * 1024 * 1024,
    )
    stored_image_max_dimension: int = Field(default=2048, ge=512, le=4096)
    stored_image_jpeg_quality: int = Field(default=90, ge=70, le=95)
    diagnosis_low_confidence_threshold: float = Field(default=0.50, gt=0, lt=1)
    diagnosis_high_confidence_threshold: float = Field(default=0.75, gt=0, lt=1)

    @property
    def cognito_configured(self) -> bool:
        return bool(self.cognito_user_pool_id and self.cognito_app_client_id)


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings instance."""

    return Settings()
