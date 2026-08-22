"""Pydantic Settings configuration boundary."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, model_validator
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
    database_pool_size: int = Field(default=10, ge=1, le=100)
    database_max_overflow: int = Field(default=10, ge=0, le=100)

    aws_region: str = "ap-south-1"
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""
    cognito_jwks_cache_seconds: int = Field(default=3600, ge=60, le=86400)
    cognito_jwks_min_refresh_seconds: int = Field(default=60, ge=10, le=3600)
    cognito_jwks_max_bytes: int = Field(default=256 * 1024, ge=1024, le=1024 * 1024)
    external_request_timeout_seconds: float = Field(default=5.0, gt=0, le=30)
    openai_request_timeout_seconds: float = Field(default=45.0, gt=5, le=120)

    openai_api_key: str = ""
    openai_primary_model: Literal["gpt-5"] = "gpt-5"
    openai_light_model: Literal["gpt-5-mini"] = "gpt-5-mini"
    leaf_inference_backend: Literal["disabled", "openai_vision"] = "openai_vision"
    openai_leaf_model: Literal["gpt-5", "gpt-5-mini"] = "gpt-5"
    openai_leaf_confidence_cap: float = Field(default=0.74, ge=0.1, lt=0.75)
    openai_progression_model: Literal["gpt-5", "gpt-5-mini"] = "gpt-5"
    openai_transcription_model: Literal["gpt-4o-mini-transcribe", "gpt-4o-transcribe"] = (
        "gpt-4o-mini-transcribe"
    )
    openai_speech_model: Literal["tts-1", "tts-1-hd"] = "tts-1"
    openai_speech_voice: Literal[
        "alloy", "ash", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer"
    ] = "nova"
    openai_audio_timeout_seconds: float = Field(default=45.0, gt=5, le=120)
    voice_max_audio_bytes: int = Field(default=10 * 1024 * 1024, ge=1024, le=25 * 1024 * 1024)
    voice_max_transcript_characters: int = Field(default=4000, ge=100, le=12000)
    voice_max_speech_characters: int = Field(default=12000, ge=100, le=20000)
    voice_transcriptions_per_minute: int = Field(default=6, ge=1, le=60)
    voice_speech_requests_per_minute: int = Field(default=12, ge=1, le=120)
    progression_requests_per_minute: int = Field(default=4, ge=1, le=60)
    diagnosis_requests_per_minute: int = Field(default=6, ge=1, le=60)
    chat_requests_per_minute: int = Field(default=8, ge=1, le=120)
    weather_requests_per_minute: int = Field(default=12, ge=1, le=120)
    auth_requests_per_minute: int = Field(default=10, ge=1, le=120)
    auth_ip_requests_per_minute: int = Field(default=120, ge=1, le=1000)
    auth_rate_limit_hmac_key: SecretStr = SecretStr("")
    memory_connections_per_minute: int = Field(default=2, ge=1, le=30)
    paid_provider_max_concurrent_requests: int = Field(default=4, ge=1, le=32)
    mem0_api_key: str = ""
    memory_capture_interval_seconds: float = Field(default=30.0, ge=1, le=3600)
    memory_capture_batch_size: int = Field(default=20, ge=1, le=100)
    memory_capture_max_attempts: int = Field(default=10, ge=1, le=100)

    openweather_api_key: str = ""
    openweather_base_url: str = "https://api.openweathermap.org/data/2.5"
    open_meteo_base_url: str = "https://api.open-meteo.com/v1"
    open_meteo_geocoding_base_url: str = "https://geocoding-api.open-meteo.com/v1"
    weather_cache_seconds: int = Field(default=3600, ge=300, le=21600)
    weather_max_stale_seconds: int = Field(default=21600, ge=3600, le=86400)

    storage_backend: Literal["local", "s3"] = "local"
    local_storage_path: str = "./storage"
    s3_bucket: str = ""
    s3_key_prefix: str = "private"
    s3_kms_key_id: str = ""
    s3_expected_bucket_owner: str = ""
    s3_endpoint_url: str = ""
    max_image_bytes: int = Field(default=10 * 1024 * 1024, ge=1024, le=50 * 1024 * 1024)
    max_diagnosis_upload_bytes: int = Field(
        default=50 * 1024 * 1024,
        ge=1024,
        le=250 * 1024 * 1024,
    )
    max_diagnosis_images: int = Field(default=12, ge=1, le=50)
    max_diagnosis_case_images: int = Field(default=36, ge=2, le=200)
    diagnosis_capture_future_tolerance_minutes: int = Field(default=10, ge=0, le=1440)
    diagnosis_capture_max_age_days: int = Field(default=3650, ge=1, le=36500)
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
    def validate_settings(self) -> "Settings":
        if self.storage_backend == "s3" and not self.s3_bucket.strip():
            raise ValueError("S3_BUCKET_REQUIRED")
        if not self.s3_key_prefix.replace("-", "").replace("_", "").isalnum():
            raise ValueError("S3_KEY_PREFIX_INVALID")
        if self.s3_expected_bucket_owner and not (
            self.s3_expected_bucket_owner.isdigit() and len(self.s3_expected_bucket_owner) == 12
        ):
            raise ValueError("S3_EXPECTED_BUCKET_OWNER_INVALID")
        if self.app_env == "production":
            if self.debug:
                raise ValueError("PRODUCTION_DEBUG_FORBIDDEN")
            database_url = self.database_url.casefold()
            uses_tls = "ssl=" in database_url or "sslmode=" in database_url
            if "localhost" in database_url or not uses_tls:
                raise ValueError("PRODUCTION_DATABASE_TLS_REQUIRED")
            if self.storage_backend != "s3":
                raise ValueError("PRODUCTION_REQUIRES_S3_STORAGE")
            if not self.s3_expected_bucket_owner:
                raise ValueError("PRODUCTION_REQUIRES_S3_BUCKET_OWNER")
            if self.s3_endpoint_url:
                raise ValueError("PRODUCTION_S3_ENDPOINT_OVERRIDE_FORBIDDEN")
            if not self.cognito_configured:
                raise ValueError("PRODUCTION_REQUIRES_COGNITO")
            if len(self.auth_rate_limit_hmac_key.get_secret_value()) < 32:
                raise ValueError("PRODUCTION_REQUIRES_AUTH_RATE_LIMIT_HMAC_KEY")
            if not self.openai_api_key.strip():
                raise ValueError("PRODUCTION_REQUIRES_OPENAI")
            if self.leaf_inference_backend == "disabled":
                raise ValueError("PRODUCTION_REQUIRES_LEAF_INFERENCE")
            if not self.openweather_configured:
                raise ValueError("PRODUCTION_REQUIRES_OPENWEATHER")
            if not self.mem0_api_key.strip():
                raise ValueError("PRODUCTION_REQUIRES_MEM0")
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
