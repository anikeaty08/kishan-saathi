"""Unit tests for strict external weather response handling."""

from datetime import UTC, datetime

import httpx
import pytest

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.weather.open_meteo import OpenMeteoForecastProvider
from app.integrations.weather.openweather import OpenWeatherCurrentProvider


@pytest.mark.asyncio
async def test_openweather_parses_current_conditions() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["units"] == "metric"
        return httpx.Response(
            200,
            json={
                "dt": int(datetime.now(tz=UTC).timestamp()),
                "name": "Pune",
                "weather": [{"id": 500, "description": "light rain", "icon": "10d"}],
                "main": {"temp": 27, "feels_like": 29, "humidity": 78},
                "wind": {"speed": 3.2},
                "rain": {"1h": 1.5},
            },
        )

    client = httpx.AsyncClient(
        base_url="https://weather.test", transport=httpx.MockTransport(handler)
    )
    provider = OpenWeatherCurrentProvider(
        Settings(_env_file=None, openweather_api_key="key"), client=client
    )

    value = await provider.current(latitude=18.5, longitude=73.8)
    await client.aclose()

    assert value.location_name == "Pune"
    assert value.rain_last_hour_mm == 1.5


@pytest.mark.asyncio
async def test_openweather_empty_weather_is_provider_error() -> None:
    client = httpx.AsyncClient(
        base_url="https://weather.test",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                json={
                    "dt": 1,
                    "weather": [],
                    "main": {"temp": 1, "feels_like": 1, "humidity": 1},
                },
            )
        ),
    )
    provider = OpenWeatherCurrentProvider(
        Settings(_env_file=None, openweather_api_key="key"), client=client
    )

    with pytest.raises(ApplicationError) as raised:
        await provider.current(latitude=18.5, longitude=73.8)
    await client.aclose()

    assert raised.value.code == "CURRENT_WEATHER_INVALID_RESPONSE"


@pytest.mark.asyncio
async def test_openweather_malformed_nested_shape_is_provider_error() -> None:
    client = httpx.AsyncClient(
        base_url="https://weather.test",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                json={
                    "dt": 1,
                    "weather": [{"id": 500, "description": "rain"}],
                    "main": {"temp": 1, "feels_like": 1, "humidity": 1},
                    "wind": [],
                },
            )
        ),
    )
    provider = OpenWeatherCurrentProvider(
        Settings(_env_file=None, openweather_api_key="key"), client=client
    )

    with pytest.raises(ApplicationError) as raised:
        await provider.current(latitude=18.5, longitude=73.8)
    await client.aclose()

    assert raised.value.code == "CURRENT_WEATHER_INVALID_RESPONSE"


@pytest.mark.asyncio
async def test_open_meteo_parses_daily_forecast() -> None:
    client = httpx.AsyncClient(
        base_url="https://forecast.test",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                json={
                    "timezone": "Asia/Kolkata",
                    "daily": {
                        "time": ["2026-08-12"],
                        "weather_code": [61],
                        "temperature_2m_min": [22],
                        "temperature_2m_max": [31],
                        "precipitation_sum": [4.5],
                        "precipitation_probability_max": [70],
                        "wind_speed_10m_max": [18],
                    },
                },
            )
        ),
    )
    provider = OpenMeteoForecastProvider(Settings(_env_file=None), client=client)

    value = await provider.forecast(latitude=18.5, longitude=73.8)
    await client.aclose()

    assert value.timezone == "Asia/Kolkata"
    assert value.days[0].precipitation_probability_max_percent == 70


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("provider_kind", "expected_code"),
    [
        ("current", "CURRENT_WEATHER_UNAVAILABLE"),
        ("forecast", "FORECAST_WEATHER_UNAVAILABLE"),
    ],
)
async def test_weather_providers_normalize_protocol_failures(
    provider_kind: str, expected_code: str
) -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        raise httpx.RemoteProtocolError("upstream disconnected")

    client = httpx.AsyncClient(
        base_url="https://weather.test", transport=httpx.MockTransport(handler)
    )
    if provider_kind == "current":
        current_provider = OpenWeatherCurrentProvider(
            Settings(_env_file=None, openweather_api_key="key"), client=client
        )
        with pytest.raises(ApplicationError) as raised:
            await current_provider.current(latitude=18.5, longitude=73.8)
    else:
        forecast_provider = OpenMeteoForecastProvider(Settings(_env_file=None), client=client)
        with pytest.raises(ApplicationError) as raised:
            await forecast_provider.forecast(latitude=18.5, longitude=73.8)
    await client.aclose()

    assert raised.value.code == expected_code
