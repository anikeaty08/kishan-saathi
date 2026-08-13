"""Startup dependency container and provider/plugin bindings."""

from app.core.config import Settings
from app.integrations.auth.cognito import CognitoAuthProvider
from app.integrations.auth.provider import AuthProvider, UnavailableAuthProvider
from app.integrations.geocoding.open_meteo import OpenMeteoGeocodingProvider
from app.integrations.geocoding.provider import GeocodingProvider
from app.integrations.inference.provider import (
    LeafInferenceProvider,
    UnavailableLeafInferenceProvider,
)
from app.integrations.llm.openai_responses import OpenAIResponsesProvider
from app.integrations.llm.provider import LLMProvider, UnavailableLLMProvider
from app.integrations.memory.mem0 import Mem0MemoryProvider
from app.integrations.memory.provider import MemoryProvider, UnavailableMemoryProvider
from app.integrations.progression.openai_responses import OpenAIProgressionProvider
from app.integrations.progression.provider import (
    ProgressionProvider,
    UnavailableProgressionProvider,
)
from app.integrations.storage.local import LocalObjectStorage
from app.integrations.storage.provider import ObjectStorageProvider
from app.integrations.weather.open_meteo import OpenMeteoForecastProvider
from app.integrations.weather.openweather import (
    OpenWeatherCurrentProvider,
    UnavailableCurrentWeatherProvider,
)
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider


def build_auth_provider(settings: Settings) -> AuthProvider:
    """Select the configured authentication adapter once during startup."""

    if not settings.cognito_configured:
        return UnavailableAuthProvider()
    return CognitoAuthProvider(settings)


def build_object_storage(settings: Settings) -> ObjectStorageProvider:
    """Select local private storage until an S3 adapter is configured."""

    return LocalObjectStorage(settings.local_storage_path)


def build_leaf_inference_provider(_settings: Settings) -> LeafInferenceProvider:
    """Fail honestly until the evaluated checkpoint or service is supplied."""

    return UnavailableLeafInferenceProvider()


def build_llm_provider(settings: Settings) -> LLMProvider:
    if not settings.openai_api_key:
        return UnavailableLLMProvider()
    return OpenAIResponsesProvider(settings)


def build_memory_provider(settings: Settings) -> MemoryProvider:
    if not settings.mem0_api_key:
        return UnavailableMemoryProvider()
    return Mem0MemoryProvider(settings.mem0_api_key)


def build_progression_provider(settings: Settings) -> ProgressionProvider:
    """Bind visual comparison only when the shared OpenAI credential exists."""

    if not settings.openai_api_key:
        return UnavailableProgressionProvider()
    return OpenAIProgressionProvider(settings)


def build_current_weather_provider(settings: Settings) -> CurrentWeatherProvider:
    if not settings.openweather_api_key:
        return UnavailableCurrentWeatherProvider()
    return OpenWeatherCurrentProvider(settings)


def build_forecast_weather_provider(settings: Settings) -> ForecastWeatherProvider:
    return OpenMeteoForecastProvider(settings)


def build_geocoding_provider(settings: Settings) -> GeocodingProvider:
    return OpenMeteoGeocodingProvider(settings)
