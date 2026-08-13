"""Pydantic Settings configuration boundary."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
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
    openai_request_timeout_seconds: float = Field(default=45.0, gt=5, le=120)

    openai_api_key: str = ""
    openai_primary_model: Literal["gpt-5"] = "gpt-5"
    openai_light_model: Literal["gpt-5-mini"] = "gpt-5-mini"
    openai_progression_model: Literal["gpt-5", "gpt-5-mini"] = "gpt-5"
    mem0_api_key: str = ""
    memory_capture_interval_seconds: float = Field(default=30.0, ge=1, le=3600)
    memory_capture_batch_size: int = Field(default=20, ge=1, le=100)
    memory_capture_max_attempts: int = Field(default=10, ge=1, le=100)
    chat_turn_interval_seconds: float = Field(default=0.5, ge=0.1, le=30)
    chat_turn_batch_size: int = Field(default=10, ge=1, le=50)
    chat_turn_max_attempts: int = Field(default=3, ge=1, le=10)
    chat_turn_lease_seconds: int = Field(default=180, ge=30, le=900)
    chat_turn_processing_timeout_seconds: int = Field(default=120, ge=10, le=840)
    chat_turn_backoff_base_seconds: int = Field(default=2, ge=1, le=60)
    chat_turn_backoff_max_seconds: int = Field(default=30, ge=1, le=300)

    openweather_api_key: str = ""
    openweather_base_url: str = "https://api.openweathermap.org/data/2.5"
    open_meteo_base_url: str = "https://api.open-meteo.com/v1"
    open_meteo_geocoding_base_url: str = "https://geocoding-api.open-meteo.com/v1"
    weather_cache_seconds: int = Field(default=3600, ge=300, le=21600)
    weather_max_stale_seconds: int = Field(default=21600, ge=3600, le=86400)

    local_storage_path: str = "./storage"
    max_image_bytes: int = Field(default=10 * 1024 * 1024, ge=1024, le=50 * 1024 * 1024)
    max_diagnosis_upload_bytes: int = Field(
        default=50 * 1024 * 1024,
        ge=1024,
        le=250 * 1024 * 1024,
    )
    max_diagnosis_images: int = Field(default=12, ge=1, le=50)
    stored_image_max_dimension: int = Field(default=2048, ge=512, le=4096)
    source_image_max_pixels: int = Field(default=25_000_000, ge=1_000_000, le=100_000_000)
    stored_image_jpeg_quality: int = Field(default=90, ge=70, le=95)
    object_cleanup_interval_seconds: float = Field(default=30.0, ge=1, le=3600)
    object_cleanup_batch_size: int = Field(default=50, ge=1, le=500)
    object_cleanup_backoff_base_seconds: int = Field(default=60, ge=1, le=3600)
    object_cleanup_backoff_max_seconds: int = Field(default=21600, ge=60, le=86400)
    diagnosis_low_confidence_threshold: float = Field(default=0.50, gt=0, lt=1)
    diagnosis_high_confidence_threshold: float = Field(default=0.75, gt=0, lt=1)
    progression_max_images_per_timepoint: int = Field(default=3, ge=1, le=6)
    progression_max_total_image_bytes: int = Field(
        default=15 * 1024 * 1024,
        ge=1024,
        le=60 * 1024 * 1024,
    )
    progression_history_scan_limit: int = Field(default=20, ge=2, le=100)
    progression_min_image_dimension: int = Field(default=160, ge=32, le=1024)
    progression_min_image_quality_score: float = Field(default=0.45, ge=0, le=1)

    @model_validator(mode="after")
    def validate_chat_turn_timing(self) -> "Settings":
        if self.chat_turn_processing_timeout_seconds >= self.chat_turn_lease_seconds:
            raise ValueError("CHAT_TURN_TIMEOUT_MUST_BE_SHORTER_THAN_LEASE")
        return self

    @property
    def cognito_configured(self) -> bool:
        return bool(self.cognito_user_pool_id and self.cognito_app_client_id)

    @property
    def openweather_configured(self) -> bool:
        return bool(self.openweather_api_key)


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings instance."""

    return Settings()
