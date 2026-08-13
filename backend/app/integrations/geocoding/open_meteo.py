"""Open-Meteo Geocoding API adapter."""

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.geocoding.provider import GeocodingResult


class _GeocodingEnvelope(BaseModel):
    model_config = ConfigDict(extra="ignore")

    results: list[GeocodingResult] = Field(default_factory=list)


class OpenMeteoGeocodingProvider:
    def __init__(self, settings: Settings, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=settings.open_meteo_geocoding_base_url,
            timeout=settings.external_request_timeout_seconds,
        )
        self._owns_client = client is None

    async def search(self, *, query: str, language: str, limit: int) -> tuple[GeocodingResult, ...]:
        try:
            response = await self._client.get(
                "/search",
                params={
                    "name": query,
                    "count": limit,
                    "language": language,
                    "format": "json",
                },
            )
            response.raise_for_status()
            payload = _GeocodingEnvelope.model_validate(response.json())
            return tuple(payload.results)
        except httpx.HTTPStatusError as exc:
            raise ApplicationError(code="GEOCODING_PROVIDER_ERROR", status_code=502) from exc
        except httpx.RequestError as exc:
            raise ApplicationError(code="GEOCODING_UNAVAILABLE", status_code=503) from exc
        except (ValidationError, ValueError) as exc:
            raise ApplicationError(code="GEOCODING_INVALID_RESPONSE", status_code=502) from exc

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()
