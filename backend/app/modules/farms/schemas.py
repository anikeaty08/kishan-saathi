"""Typed API contracts for farms, plots, crops, and activities."""

from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.modules.users.schemas import AreaUnit

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
Stage = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class CropCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Name
    stage: Stage
    variety: Name | None = None
    sowing_or_transplant_date: date | None = None


class CropResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    plot_id: UUID
    name: str
    stage: str
    variety: str | None
    sowing_or_transplant_date: date | None
    cycle_started_on: date
    cycle_ended_on: date | None
    created_at: datetime
    updated_at: datetime


class FarmCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Name


class FarmUpdate(FarmCreate):
    pass


class FarmResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    created_at: datetime
    updated_at: datetime


class PlotCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Name
    farm_id: UUID | None = None
    latitude: Decimal = Field(ge=-90, le=90, max_digits=9, decimal_places=6)
    longitude: Decimal = Field(ge=-180, le=180, max_digits=9, decimal_places=6)
    location_label: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=255)
    ] | None = None
    area_value: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=3)
    area_unit: AreaUnit | None = None
    soil_notes: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=2000)
    ] | None = None
    irrigation_details: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=2000)
    ] | None = None
    crops: list[CropCreate] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def area_is_complete(self) -> Self:
        if (self.area_value is None) != (self.area_unit is None):
            raise ValueError("PLOT_AREA_INCOMPLETE")
        return self


class PlotUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Name | None = None
    farm_id: UUID | None = None
    latitude: Decimal | None = Field(default=None, ge=-90, le=90, max_digits=9, decimal_places=6)
    longitude: Decimal | None = Field(default=None, ge=-180, le=180, max_digits=9, decimal_places=6)
    location_label: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=255)
    ] | None = None
    area_value: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=3)
    area_unit: AreaUnit | None = None
    soil_notes: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=2000)
    ] | None = None
    irrigation_details: Annotated[
        str, StringConstraints(strip_whitespace=True, max_length=2000)
    ] | None = None

    @model_validator(mode="after")
    def require_non_null_changes(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("PLOT_UPDATE_EMPTY")
        required_non_null = {"name", "latitude", "longitude"}
        if any(getattr(self, field) is None for field in self.model_fields_set & required_non_null):
            raise ValueError("PLOT_REQUIRED_FIELD_NULL")
        if bool({"area_value", "area_unit"} & self.model_fields_set) and (
            self.area_value is None or self.area_unit is None
        ):
            raise ValueError("PLOT_AREA_INCOMPLETE")
        return self


class PlotResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    farm_id: UUID | None
    name: str
    latitude: Decimal
    longitude: Decimal
    location_label: str | None
    area_value: Decimal | None
    area_unit: AreaUnit | None
    soil_notes: str | None
    irrigation_details: str | None
    crops: list[CropResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class CropStageUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    stage: Stage


class ActivityCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crop_id: UUID | None = None
    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)]
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=4000)] | None = None
    occurred_at: datetime


class ActivityUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)
    ] | None = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=4000)] | None = None
    occurred_at: datetime | None = None

    @model_validator(mode="after")
    def require_change(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("ACTIVITY_UPDATE_EMPTY")
        if any(getattr(self, field) is None for field in self.model_fields_set - {"notes"}):
            raise ValueError("ACTIVITY_REQUIRED_FIELD_NULL")
        return self


class ActivityResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    plot_id: UUID
    crop_id: UUID | None
    title: str
    notes: str | None
    occurred_at: datetime
    created_at: datetime
    updated_at: datetime


class ActivityPhotoResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    activity_id: UUID
    size_bytes: int
    width: int
    height: int
    created_at: datetime


class DeletionImpactResponse(BaseModel):
    entity_id: UUID
    can_delete: bool
    linked_records: dict[str, int]
