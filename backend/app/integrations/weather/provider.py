"""Provider-neutral current-weather and forecast contracts."""

from datetime import date, datetime
from typing import Protocol

from pydantic import BaseModel, ConfigDict, Field


class CurrentWeather(BaseModel):
    model_config = ConfigDict(extra="forbid")
    observed_at: datetime
    location_name: str | None = None
    condition_code: int
    condition: str
    icon_code: str | None = None
    temperature_c: float
    feels_like_c: float
    humidity_percent: int = Field(ge=0, le=100)
    wind_speed_mps: float = Field(ge=0)
    rain_last_hour_mm: float = Field(default=0, ge=0)


class ForecastDay(BaseModel):
    model_config = ConfigDict(extra="forbid")
    date: date
    condition_code: int
    temperature_min_c: float
    temperature_max_c: float
    precipitation_sum_mm: float = Field(ge=0)
    precipitation_probability_max_percent: int = Field(ge=0, le=100)
    wind_speed_max_kmh: float = Field(ge=0)


class PlotForecast(BaseModel):
    model_config = ConfigDict(extra="forbid")
    timezone: str
    generated_at: datetime
    days: list[ForecastDay]


class CurrentWeatherProvider(Protocol):
    name: str

    async def current(self, *, latitude: float, longitude: float) -> CurrentWeather: ...

    async def close(self) -> None: ...


class ForecastWeatherProvider(Protocol):
    name: str

    async def forecast(self, *, latitude: float, longitude: float) -> PlotForecast: ...

    async def close(self) -> None: ...
