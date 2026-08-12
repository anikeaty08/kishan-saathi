"""Location-name search contracts."""

from typing import Protocol

from pydantic import BaseModel, ConfigDict, Field


class GeocodingResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    country: str | None = None
    admin1: str | None = None
    admin2: str | None = None
    timezone: str | None = None


class GeocodingProvider(Protocol):
    async def search(
        self, *, query: str, language: str, limit: int
    ) -> tuple[GeocodingResult, ...]: ...

    async def close(self) -> None: ...
