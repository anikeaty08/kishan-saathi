"""Authenticated app-facing weather endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.dependencies import get_paid_operation_rate_limiter
from app.core.rate_limits import PaidOperationRateLimiter
from app.modules.users.dependencies import get_current_farmer_id
from app.modules.weather.dependencies import get_weather_service
from app.modules.weather.schemas import (
    CurrentWeatherResponse,
    PhoneLocation,
    PlotForecastResponse,
)
from app.modules.weather.service import WeatherService

router = APIRouter(prefix="/weather", tags=["weather"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[WeatherService, Depends(get_weather_service)]


@router.post("/current", response_model=CurrentWeatherResponse)
async def current_phone_weather(
    location: PhoneLocation,
    farmer_id: FarmerId,
    service: Service,
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
) -> CurrentWeatherResponse:
    """Home/weather-screen conditions from the phone's current coordinates."""

    async with limiter.request(farmer_id, "weather"):
        return await service.current_for_phone(
            farmer_id, latitude=location.latitude, longitude=location.longitude
        )


@router.get("/plots/{plot_id}/forecast", response_model=PlotForecastResponse)
async def plot_forecast(
    plot_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
) -> PlotForecastResponse:
    """App plot view; the same controlled operation backs the LLM forecast tool."""

    async with limiter.request(farmer_id, "weather"):
        return await service.forecast_for_plot(farmer_id, plot_id)


@router.get("/plots/{plot_id}/current", response_model=CurrentWeatherResponse)
async def plot_current_weather(
    plot_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
) -> CurrentWeatherResponse:
    async with limiter.request(farmer_id, "weather"):
        return await service.current_for_plot(farmer_id, plot_id)
