"""Database-backed weather snapshots; no continuously running cache service."""

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class WeatherSnapshot(Base):
    """Latest provider response for one farmer, location, and weather purpose."""

    __tablename__ = "weather_snapshots"
    __table_args__ = (
        UniqueConstraint(
            "farmer_id", "weather_type", "location_key", name="uq_weather_snapshot_cache_key"
        ),
        CheckConstraint(
            "weather_type IN ('current_phone', 'current_plot', 'plot_forecast')",
            name="ck_weather_snapshots_type",
        ),
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_weather_latitude"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_weather_longitude"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="CASCADE"), index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="CASCADE"), nullable=True, index=True
    )
    weather_type: Mapped[str] = mapped_column(String(24), index=True)
    location_key: Mapped[str] = mapped_column(String(64))
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    provider: Mapped[str] = mapped_column(String(50))
    payload: Mapped[dict[str, object]] = mapped_column(JSON)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
