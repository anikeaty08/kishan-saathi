"""On-demand one-hour caching for current weather and plot forecasts."""

from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider
from app.modules.farms.repository import FarmRepository
from app.modules.weather.models import WeatherSnapshot
from app.modules.weather.repository import WeatherRepository
from app.modules.weather.schemas import CurrentWeatherResponse, PlotForecastResponse


class WeatherService:
    def __init__(
        self,
        *,
        settings: Settings,
        repository: WeatherRepository,
        farms: FarmRepository,
        current_provider: CurrentWeatherProvider,
        forecast_provider: ForecastWeatherProvider,
    ) -> None:
        self._max_age = timedelta(seconds=settings.weather_cache_seconds)
        self._max_stale_age = timedelta(seconds=settings.weather_max_stale_seconds)
        self._repository = repository
        self._farms = farms
        self._current_provider = current_provider
        self._forecast_provider = forecast_provider

    async def current_for_phone(
        self, farmer_id: UUID, *, latitude: Decimal, longitude: Decimal
    ) -> CurrentWeatherResponse:
        key = self._location_key(latitude, longitude)
        cached = await self._repository.get(
            farmer_id, weather_type="current_phone", location_key=key
        )
        if cached is not None and self._fresh(cached):
            return self._current_response(cached, stale=False)
        try:
            value = await self._current_provider.current(
                latitude=float(latitude), longitude=float(longitude)
            )
        except ApplicationError:
            if cached is not None and self._stale_allowed(cached):
                return self._current_response(cached, stale=True)
            raise
        snapshot = await self._save(
            cached,
            farmer_id=farmer_id,
            plot_id=None,
            weather_type="current_phone",
            location_key=key,
            latitude=latitude,
            longitude=longitude,
            provider=self._current_provider.name,
            payload=value.model_dump(mode="json"),
        )
        return self._current_response(snapshot, stale=False)

    async def current_for_plot(self, farmer_id: UUID, plot_id: UUID) -> CurrentWeatherResponse:
        """Use the farmer-confirmed plot pointer, never client-supplied coordinates."""

        plot = await self._farms.get_plot(farmer_id, plot_id)
        if plot is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        key = str(plot.id)
        cached = await self._repository.get(
            farmer_id, weather_type="current_plot", location_key=key
        )
        cache_matches_plot = cached is not None and self._same_location(
            cached, plot.latitude, plot.longitude
        )
        if cache_matches_plot and cached is not None and self._fresh(cached):
            return self._current_response(cached, stale=False)
        try:
            value = await self._current_provider.current(
                latitude=float(plot.latitude), longitude=float(plot.longitude)
            )
        except ApplicationError:
            if cache_matches_plot and cached is not None and self._stale_allowed(cached):
                return self._current_response(cached, stale=True)
            raise
        snapshot = await self._save(
            cached,
            farmer_id=farmer_id,
            plot_id=plot.id,
            weather_type="current_plot",
            location_key=key,
            latitude=plot.latitude,
            longitude=plot.longitude,
            provider=self._current_provider.name,
            payload=value.model_dump(mode="json"),
        )
        return self._current_response(snapshot, stale=False)

    async def forecast_for_plot(self, farmer_id: UUID, plot_id: UUID) -> PlotForecastResponse:
        """Reuse a fresh plot forecast and retain stale data only as a marked fallback."""

        plot = await self._farms.get_plot(farmer_id, plot_id)
        if plot is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        key = str(plot.id)
        cached = await self._repository.get(
            farmer_id, weather_type="plot_forecast", location_key=key
        )
        cache_matches_plot = cached is not None and self._same_location(
            cached, plot.latitude, plot.longitude
        )
        if cache_matches_plot and cached is not None and self._fresh(cached):
            return self._forecast_response(cached, stale=False)
        try:
            value = await self._forecast_provider.forecast(
                latitude=float(plot.latitude), longitude=float(plot.longitude)
            )
        except ApplicationError:
            if cache_matches_plot and cached is not None and self._stale_allowed(cached):
                return self._forecast_response(cached, stale=True)
            raise
        snapshot = await self._save(
            cached,
            farmer_id=farmer_id,
            plot_id=plot.id,
            weather_type="plot_forecast",
            location_key=key,
            latitude=plot.latitude,
            longitude=plot.longitude,
            provider=self._forecast_provider.name,
            payload=value.model_dump(mode="json"),
        )
        return self._forecast_response(snapshot, stale=False)

    def _fresh(self, snapshot: WeatherSnapshot) -> bool:
        fetched_at = snapshot.fetched_at
        if fetched_at.tzinfo is None:
            fetched_at = fetched_at.replace(tzinfo=UTC)
        return datetime.now(tz=UTC) - fetched_at <= self._max_age

    def _stale_allowed(self, snapshot: WeatherSnapshot) -> bool:
        fetched_at = snapshot.fetched_at
        if fetched_at.tzinfo is None:
            fetched_at = fetched_at.replace(tzinfo=UTC)
        return datetime.now(tz=UTC) - fetched_at <= self._max_stale_age

    @staticmethod
    def _same_location(snapshot: WeatherSnapshot, latitude: Decimal, longitude: Decimal) -> bool:
        return snapshot.latitude == latitude and snapshot.longitude == longitude

    async def _save(
        self,
        snapshot: WeatherSnapshot | None,
        *,
        farmer_id: UUID,
        plot_id: UUID | None,
        weather_type: str,
        location_key: str,
        latitude: Decimal,
        longitude: Decimal,
        provider: str,
        payload: dict[str, object],
    ) -> WeatherSnapshot:
        now = datetime.now(tz=UTC)
        del snapshot
        return await self._repository.upsert(
            {
                "farmer_id": farmer_id,
                "plot_id": plot_id,
                "weather_type": weather_type,
                "location_key": location_key,
                "latitude": latitude,
                "longitude": longitude,
                "provider": provider,
                "payload": payload,
                "fetched_at": now,
            }
        )

    @staticmethod
    def _location_key(latitude: Decimal, longitude: Decimal) -> str:
        return f"{latitude.quantize(Decimal('0.0001'))}:{longitude.quantize(Decimal('0.0001'))}"

    @staticmethod
    def _current_response(snapshot: WeatherSnapshot, *, stale: bool) -> CurrentWeatherResponse:
        return CurrentWeatherResponse(
            weather=snapshot.payload,
            provider=snapshot.provider,
            fetched_at=snapshot.fetched_at,
            is_stale=stale,
        )

    @staticmethod
    def _forecast_response(snapshot: WeatherSnapshot, *, stale: bool) -> PlotForecastResponse:
        return PlotForecastResponse(
            forecast=snapshot.payload,
            provider=snapshot.provider,
            fetched_at=snapshot.fetched_at,
            is_stale=stale,
        )
