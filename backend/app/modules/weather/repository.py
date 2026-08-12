"""Owner-scoped weather snapshot persistence."""

from typing import cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.weather.models import WeatherSnapshot


class WeatherRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(
        self, farmer_id: UUID, *, weather_type: str, location_key: str
    ) -> WeatherSnapshot | None:
        result = await self.session.execute(
            select(WeatherSnapshot).where(
                WeatherSnapshot.farmer_id == farmer_id,
                WeatherSnapshot.weather_type == weather_type,
                WeatherSnapshot.location_key == location_key,
            )
        )
        return result.scalar_one_or_none()

    def add(self, snapshot: WeatherSnapshot) -> None:
        self.session.add(snapshot)

    async def commit(self) -> None:
        await self.session.commit()

    async def refresh(self, snapshot: WeatherSnapshot) -> None:
        await self.session.refresh(snapshot)

    async def upsert(self, values: dict[str, object]) -> WeatherSnapshot:
        """Atomically replace a cache row on PostgreSQL; serialize on other test DBs."""

        if self.session.bind is not None and self.session.bind.dialect.name == "postgresql":
            insert_statement = postgresql_insert(WeatherSnapshot).values(**values)
            upsert_statement = insert_statement.on_conflict_do_update(
                constraint="uq_weather_snapshot_cache_key",
                set_={
                    key: value
                    for key, value in values.items()
                    if key not in {"id", "farmer_id", "weather_type", "location_key"}
                },
            ).returning(WeatherSnapshot)
            result = await self.session.execute(upsert_statement)
            snapshot = result.scalar_one()
            await self.session.commit()
            return snapshot

        existing = await self.get(
            cast(UUID, values["farmer_id"]),
            weather_type=str(values["weather_type"]),
            location_key=str(values["location_key"]),
        )
        if existing is None:
            existing = WeatherSnapshot(**values)
            self.add(existing)
        else:
            for key, value in values.items():
                if key not in {"id", "farmer_id", "weather_type", "location_key"}:
                    setattr(existing, key, value)
        await self.commit()
        await self.refresh(existing)
        return existing
