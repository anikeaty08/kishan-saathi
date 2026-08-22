"""Open-Meteo daily plot-forecast adapter."""

from datetime import UTC, date, datetime
from typing import Any

import httpx

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.weather.provider import ForecastDay, PlotForecast


class OpenMeteoForecastProvider:
    name = "open-meteo"

    def __init__(self, settings: Settings, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=settings.open_meteo_base_url,
            timeout=settings.external_request_timeout_seconds,
        )
        self._owns_client = client is None

    async def forecast(self, *, latitude: float, longitude: float) -> PlotForecast:
        try:
            response = await self._client.get(
                "/forecast",
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "daily": (
                        "weather_code,temperature_2m_max,temperature_2m_min,"
                        "precipitation_sum,precipitation_probability_max,wind_speed_10m_max"
                    ),
                    "timezone": "auto",
                    "forecast_days": 7,
                },
            )
            response.raise_for_status()
            if not response.content:
                raise ApplicationError(code="FORECAST_WEATHER_UNAVAILABLE", status_code=503)
            try:
                payload: dict[str, Any] = response.json()
            except ValueError as exc:
                raise ApplicationError(
                    code="FORECAST_WEATHER_INVALID_RESPONSE", status_code=502
                ) from exc
            daily = payload["daily"]
            days = [
                ForecastDay(
                    date=date.fromisoformat(value),
                    condition_code=daily["weather_code"][index],
                    temperature_min_c=daily["temperature_2m_min"][index],
                    temperature_max_c=daily["temperature_2m_max"][index],
                    precipitation_sum_mm=daily["precipitation_sum"][index] or 0,
                    precipitation_probability_max_percent=(
                        daily["precipitation_probability_max"][index] or 0
                    ),
                    wind_speed_max_kmh=daily["wind_speed_10m_max"][index] or 0,
                )
                for index, value in enumerate(daily["time"])
            ]
            return PlotForecast(
                timezone=payload["timezone"],
                generated_at=datetime.now(tz=UTC),
                days=days,
            )
        except httpx.HTTPStatusError as exc:
            status = 503 if exc.response.status_code >= 500 else 502
            raise ApplicationError(
                code="FORECAST_WEATHER_PROVIDER_ERROR", status_code=status
            ) from exc
        except httpx.RequestError as exc:
            raise ApplicationError(code="FORECAST_WEATHER_UNAVAILABLE", status_code=503) from exc
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise ApplicationError(
                code="FORECAST_WEATHER_INVALID_RESPONSE", status_code=502
            ) from exc

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()
