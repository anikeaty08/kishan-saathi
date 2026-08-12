"""Request-scoped weather dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import (
    get_app_settings,
    get_current_weather_provider,
    get_db_session,
    get_forecast_weather_provider,
)
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider
from app.modules.farms.repository import FarmRepository
from app.modules.weather.repository import WeatherRepository
from app.modules.weather.service import WeatherService


def get_weather_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    current_provider: Annotated[
        CurrentWeatherProvider, Depends(get_current_weather_provider)
    ],
    forecast_provider: Annotated[
        ForecastWeatherProvider, Depends(get_forecast_weather_provider)
    ],
) -> WeatherService:
    return WeatherService(
        settings=settings,
        repository=WeatherRepository(session),
        farms=FarmRepository(session),
        current_provider=current_provider,
        forecast_provider=forecast_provider,
    )
