"""OpenWeather current-conditions adapter."""

from datetime import UTC, datetime
from typing import Any

import httpx

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.weather.provider import CurrentWeather


class OpenWeatherCurrentProvider:
    name = "openweather"

    def __init__(self, settings: Settings, *, client: httpx.AsyncClient | None = None) -> None:
        self._api_key = settings.openweather_api_key
        self._client = client or httpx.AsyncClient(
            base_url=settings.openweather_base_url,
            timeout=settings.external_request_timeout_seconds,
        )
        self._owns_client = client is None

    async def current(self, *, latitude: float, longitude: float) -> CurrentWeather:
        try:
            response = await self._client.get(
                "/weather",
                params={
                    "lat": latitude,
                    "lon": longitude,
                    "appid": self._api_key,
                    "units": "metric",
                },
            )
            response.raise_for_status()
            if not response.content:
                raise ApplicationError(code="CURRENT_WEATHER_UNAVAILABLE", status_code=503)
            try:
                payload: dict[str, Any] = response.json()
            except ValueError as exc:
                raise ApplicationError(
                    code="CURRENT_WEATHER_INVALID_RESPONSE", status_code=502
                ) from exc
            weather = payload["weather"][0]
            main = payload["main"]
            return CurrentWeather(
                observed_at=datetime.fromtimestamp(payload["dt"], tz=UTC),
                location_name=payload.get("name") or None,
                condition_code=weather["id"],
                condition=weather["description"],
                icon_code=weather.get("icon"),
                temperature_c=main["temp"],
                feels_like_c=main["feels_like"],
                humidity_percent=main["humidity"],
                wind_speed_mps=payload.get("wind", {}).get("speed", 0),
                rain_last_hour_mm=payload.get("rain", {}).get("1h", 0),
            )
        except httpx.HTTPStatusError as exc:
            status = 503 if exc.response.status_code >= 500 else 502
            raise ApplicationError(
                code="CURRENT_WEATHER_PROVIDER_ERROR", status_code=status
            ) from exc
        except httpx.RequestError as exc:
            raise ApplicationError(code="CURRENT_WEATHER_UNAVAILABLE", status_code=503) from exc
        except (AttributeError, IndexError, KeyError, TypeError, ValueError) as exc:
            raise ApplicationError(
                code="CURRENT_WEATHER_INVALID_RESPONSE", status_code=502
            ) from exc

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()


class UnavailableCurrentWeatherProvider:
    name = "openweather"

    async def current(self, *, latitude: float, longitude: float) -> CurrentWeather:
        del latitude, longitude
        raise ApplicationError(code="CURRENT_WEATHER_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
