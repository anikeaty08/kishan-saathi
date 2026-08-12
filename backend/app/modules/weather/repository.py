"""Owner-scoped weather snapshot persistence."""

from uuid import UUID

from sqlalchemy import select
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
