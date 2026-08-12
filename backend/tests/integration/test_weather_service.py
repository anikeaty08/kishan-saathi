"""Integration tests for separate, owner-scoped one-hour weather caches."""

from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.weather.provider import CurrentWeather, ForecastDay, PlotForecast
from app.modules.farms.models import Plot
from app.modules.farms.repository import FarmRepository
from app.modules.users.models import FarmerProfile
from app.modules.weather.repository import WeatherRepository
from app.modules.weather.service import WeatherService

FARMER = UUID("00000000-0000-0000-0000-000000000031")
OTHER = UUID("00000000-0000-0000-0000-000000000032")


class CurrentProvider:
    name = "openweather"

    def __init__(self) -> None:
        self.calls = 0
        self.fail = False

    async def current(self, *, latitude: float, longitude: float) -> CurrentWeather:
        del latitude, longitude
        self.calls += 1
        if self.fail:
            raise ApplicationError(code="CURRENT_WEATHER_UNAVAILABLE", status_code=503)
        return CurrentWeather(
            observed_at=datetime.now(tz=UTC),
            location_name="Pune",
            condition_code=800,
            condition="clear sky",
            temperature_c=29,
            feels_like_c=30,
            humidity_percent=55,
            wind_speed_mps=2,
        )

    async def close(self) -> None:
        return None


class ForecastProvider:
    name = "open-meteo"

    def __init__(self) -> None:
        self.calls = 0

    async def forecast(self, *, latitude: float, longitude: float) -> PlotForecast:
        del latitude, longitude
        self.calls += 1
        return PlotForecast(
            timezone="Asia/Kolkata",
            generated_at=datetime.now(tz=UTC),
            days=[
                ForecastDay(
                    date=date.today(),
                    condition_code=61,
                    temperature_min_c=21,
                    temperature_max_c=30,
                    precipitation_sum_mm=8,
                    precipitation_probability_max_percent=80,
                    wind_speed_max_kmh=18,
                )
            ],
        )

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_weather_is_cached_separately_and_owner_isolation_is_enforced() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    current = CurrentProvider()
    forecast = ForecastProvider()

    try:
        async with sessions() as session:
            session.add_all([_farmer(FARMER, "owner"), _farmer(OTHER, "other")])
            plot = Plot(
                farmer_id=FARMER,
                name="North Plot",
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
            session.add(plot)
            await session.commit()
            service = _service(session, current, forecast)

            first_current = await service.current_for_phone(
                FARMER,
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
            second_current = await service.current_for_phone(
                FARMER,
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
            first_forecast = await service.forecast_for_plot(FARMER, plot.id)
            second_forecast = await service.forecast_for_plot(FARMER, plot.id)
            with pytest.raises(ApplicationError) as hidden:
                await service.forecast_for_plot(OTHER, plot.id)
    finally:
        await engine.dispose()

    assert current.calls == 1
    assert forecast.calls == 1
    assert first_current.is_stale is False
    assert second_current.fetched_at == first_current.fetched_at
    assert first_forecast.provider == "open-meteo"
    assert second_forecast.fetched_at == first_forecast.fetched_at
    assert hidden.value.code == "PLOT_NOT_FOUND"


@pytest.mark.asyncio
async def test_expired_current_cache_falls_back_with_stale_warning() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    current = CurrentProvider()
    forecast = ForecastProvider()

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "owner"))
            await session.commit()
            repository = WeatherRepository(session)
            service = WeatherService(
                settings=Settings(_env_file=None),
                repository=repository,
                farms=FarmRepository(session),
                current_provider=current,
                forecast_provider=forecast,
            )
            fresh = await service.current_for_phone(
                FARMER,
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
            snapshot = await repository.get(
                FARMER,
                weather_type="current_phone",
                location_key="18.5204:73.8567",
            )
            assert snapshot is not None
            snapshot.fetched_at = datetime.now(tz=UTC) - timedelta(hours=2)
            await repository.commit()
            current.fail = True

            stale = await service.current_for_phone(
                FARMER,
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
    finally:
        await engine.dispose()

    assert fresh.is_stale is False
    assert stale.is_stale is True
    assert stale.weather.location_name == "Pune"
    assert current.calls == 2


@pytest.mark.asyncio
async def test_changed_plot_coordinates_replace_cache_without_using_old_location() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    current = CurrentProvider()
    forecast = ForecastProvider()

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "owner"))
            plot = Plot(
                farmer_id=FARMER,
                name="Movable Plot",
                latitude=Decimal("18.520400"),
                longitude=Decimal("73.856700"),
            )
            session.add(plot)
            await session.commit()
            repository = WeatherRepository(session)
            service = WeatherService(
                settings=Settings(_env_file=None),
                repository=repository,
                farms=FarmRepository(session),
                current_provider=current,
                forecast_provider=forecast,
            )

            await service.forecast_for_plot(FARMER, plot.id)
            plot.latitude = Decimal("19.076000")
            plot.longitude = Decimal("72.877700")
            await session.commit()
            replaced = await service.forecast_for_plot(FARMER, plot.id)
            snapshots = await repository.get(
                FARMER,
                weather_type="plot_forecast",
                location_key=str(plot.id),
            )
    finally:
        await engine.dispose()

    assert forecast.calls == 2
    assert replaced.is_stale is False
    assert snapshots is not None
    assert snapshots.latitude == Decimal("19.076000")
    assert snapshots.longitude == Decimal("72.877700")


def _service(
    session: AsyncSession, current: CurrentProvider, forecast: ForecastProvider
) -> WeatherService:
    return WeatherService(
        settings=Settings(_env_file=None),
        repository=WeatherRepository(session),
        farms=FarmRepository(session),
        current_provider=current,
        forecast_provider=forecast,
    )


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
