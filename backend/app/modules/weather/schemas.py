"""Weather request and cache-aware response contracts."""

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.integrations.weather.provider import CurrentWeather, PlotForecast


class PhoneLocation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    latitude: Decimal = Field(ge=-90, le=90, max_digits=9, decimal_places=6)
    longitude: Decimal = Field(ge=-180, le=180, max_digits=9, decimal_places=6)


class CurrentWeatherResponse(BaseModel):
    weather: CurrentWeather
    provider: str
    fetched_at: datetime
    is_stale: bool


class PlotForecastResponse(BaseModel):
    forecast: PlotForecast
    provider: str
    fetched_at: datetime
    is_stale: bool
