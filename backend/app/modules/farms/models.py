"""Persistence models for farmer-owned farm organization."""

from datetime import date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class TimestampMixin:
    """Server-managed creation and update timestamps."""

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Farm(TimestampMixin, Base):
    """A lightweight named container owned by one farmer."""

    __tablename__ = "farms"
    __table_args__ = (UniqueConstraint("farmer_id", "name", name="uq_farms_owner_name"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    name: Mapped[str] = mapped_column(String(100))


class Plot(TimestampMixin, Base):
    """A farmer-confirmed geographic cultivation area."""

    __tablename__ = "plots"
    __table_args__ = (
        UniqueConstraint("farmer_id", "name", name="uq_plots_owner_name"),
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_plots_latitude"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_plots_longitude"),
        CheckConstraint("area_value IS NULL OR area_value > 0", name="ck_plots_area_positive"),
        CheckConstraint(
            "area_unit IS NULL OR area_unit IN ('acre', 'hectare')",
            name="ck_plots_area_unit",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(100))
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    location_label: Mapped[str | None] = mapped_column(String(255), nullable=True)
    area_value: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    area_unit: Mapped[str | None] = mapped_column(String(16), nullable=True)
    soil_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    irrigation_details: Mapped[str | None] = mapped_column(Text, nullable=True)


class Crop(TimestampMixin, Base):
    """One crop cycle within a plot, including intercropping."""

    __tablename__ = "crops"
    __table_args__ = (
        CheckConstraint("length(stage) BETWEEN 1 AND 100", name="ck_crops_stage_length"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    plot_id: Mapped[UUID] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), index=True
    )
    name: Mapped[str] = mapped_column(String(100))
    stage: Mapped[str] = mapped_column(String(100))
    variety: Mapped[str | None] = mapped_column(String(100), nullable=True)
    sowing_or_transplant_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    cycle_started_on: Mapped[date] = mapped_column(Date, default=date.today)
    cycle_ended_on: Mapped[date | None] = mapped_column(Date, nullable=True)


class CropStageEvent(TimestampMixin, Base):
    """Immutable crop-stage history for timelines and AI context."""

    __tablename__ = "crop_stage_events"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    crop_id: Mapped[UUID] = mapped_column(
        ForeignKey("crops.id", ondelete="CASCADE"), index=True
    )
    stage: Mapped[str] = mapped_column(String(100))
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=func.now())


class Activity(TimestampMixin, Base):
    """Farmer-entered field event linked to one plot and optional crop."""

    __tablename__ = "activities"
    __table_args__ = (
        CheckConstraint("length(title) BETWEEN 1 AND 150", name="ck_activities_title_length"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    plot_id: Mapped[UUID] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), index=True
    )
    crop_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("crops.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(150))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
