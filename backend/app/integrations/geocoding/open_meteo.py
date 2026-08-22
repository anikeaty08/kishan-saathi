"""Open-Meteo Geocoding API adapter."""

import asyncio
from time import monotonic

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.geocoding.provider import GeocodingResult


class _OpenMeteoResult(GeocodingResult):
    model_config = ConfigDict(extra="ignore")


class _GeocodingEnvelope(BaseModel):
    model_config = ConfigDict(extra="ignore")

    results: list[_OpenMeteoResult] = Field(default_factory=list)


class _NominatimAddress(BaseModel):
    model_config = ConfigDict(extra="ignore")

    postcode: str | None = None
    city: str | None = None
    town: str | None = None
    village: str | None = None
    county: str | None = None
    state: str | None = None
    country: str | None = None


class _NominatimResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    latitude: float = Field(alias="lat", ge=-90, le=90)
    longitude: float = Field(alias="lon", ge=-180, le=180)
    display_name: str
    address: _NominatimAddress = Field(default_factory=_NominatimAddress)


class OpenMeteoGeocodingProvider:
    _postal_cache_seconds = 24 * 60 * 60
    _postal_request_interval_seconds = 1.05

    def __init__(
        self,
        settings: Settings,
        *,
        client: httpx.AsyncClient | None = None,
        postal_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=settings.open_meteo_geocoding_base_url,
            timeout=settings.external_request_timeout_seconds,
        )
        self._owns_client = client is None
        self._postal_client = postal_client or httpx.AsyncClient(
            base_url=settings.nominatim_geocoding_base_url,
            timeout=settings.external_request_timeout_seconds,
        )
        self._owns_postal_client = postal_client is None
        self._postal_user_agent = (
            f"KishanSaathi/{settings.app_version} (+https://github.com/anikeaty08/kishan-saathi)"
        )
        self._postal_lock = asyncio.Lock()
        self._postal_last_request_at = 0.0
        self._postal_cache: dict[str, tuple[float, tuple[GeocodingResult, ...]]] = {}

    async def search(self, *, query: str, language: str, limit: int) -> tuple[GeocodingResult, ...]:
        normalized = query.strip()
        if len(normalized) == 6 and normalized.isascii() and normalized.isdigit():
            return await self._search_indian_postal_code(
                postal_code=normalized,
                language=language,
                limit=limit,
            )
        try:
            response = await self._client.get(
                "/search",
                params={
                    "name": normalized,
                    "count": limit,
                    "language": language,
                    "format": "json",
                    "countryCode": "IN",
                },
            )
            response.raise_for_status()
            payload = _GeocodingEnvelope.model_validate(response.json())
            return tuple(
                GeocodingResult.model_validate(result.model_dump()) for result in payload.results
            )
        except httpx.HTTPStatusError as exc:
            raise ApplicationError(code="GEOCODING_PROVIDER_ERROR", status_code=502) from exc
        except httpx.RequestError as exc:
            raise ApplicationError(code="GEOCODING_UNAVAILABLE", status_code=503) from exc
        except (ValidationError, ValueError) as exc:
            raise ApplicationError(code="GEOCODING_INVALID_RESPONSE", status_code=502) from exc

    async def _search_indian_postal_code(
        self,
        *,
        postal_code: str,
        language: str,
        limit: int,
    ) -> tuple[GeocodingResult, ...]:
        cached = self._postal_cache.get(postal_code)
        now = monotonic()
        if cached is not None and cached[0] > now:
            return cached[1][:limit]

        async with self._postal_lock:
            cached = self._postal_cache.get(postal_code)
            now = monotonic()
            if cached is not None and cached[0] > now:
                return cached[1][:limit]
            wait_seconds = self._postal_request_interval_seconds - (
                now - self._postal_last_request_at
            )
            if wait_seconds > 0:
                await asyncio.sleep(wait_seconds)
            self._postal_last_request_at = monotonic()
            try:
                response = await self._postal_client.get(
                    "/search",
                    params={
                        "postalcode": postal_code,
                        "countrycodes": "in",
                        "format": "jsonv2",
                        "addressdetails": 1,
                        "accept-language": language,
                        "limit": limit,
                    },
                    headers={"User-Agent": self._postal_user_agent},
                )
                response.raise_for_status()
                payload = [_NominatimResult.model_validate(item) for item in response.json()]
                results = tuple(self._postal_result(postal_code, item) for item in payload)
                self._postal_cache[postal_code] = (
                    monotonic() + self._postal_cache_seconds,
                    results,
                )
                return results
            except httpx.HTTPStatusError as exc:
                raise ApplicationError(code="GEOCODING_PROVIDER_ERROR", status_code=502) from exc
            except httpx.RequestError as exc:
                raise ApplicationError(code="GEOCODING_UNAVAILABLE", status_code=503) from exc
            except (TypeError, ValidationError, ValueError) as exc:
                raise ApplicationError(code="GEOCODING_INVALID_RESPONSE", status_code=502) from exc

    @staticmethod
    def _postal_result(postal_code: str, result: _NominatimResult) -> GeocodingResult:
        address = result.address
        locality = address.city or address.town or address.village or address.county
        return GeocodingResult(
            name=address.postcode or postal_code,
            latitude=result.latitude,
            longitude=result.longitude,
            country=address.country or "India",
            admin1=address.state,
            admin2=locality,
        )

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()
        if self._owns_postal_client:
            await self._postal_client.aclose()
