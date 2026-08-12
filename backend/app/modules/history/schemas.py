"""Stable, localization-ready history transport contracts."""

from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class TimelineCategory(StrEnum):
    DIAGNOSIS = "diagnosis"
    CHAT = "chat"
    REMINDER = "reminder"
    ACTIVITY = "activity"
    CROP_STAGE = "crop_stage"


class TimelineItem(BaseModel):
    """UI localizes event_code and renders structured data in the selected language."""

    model_config = ConfigDict(extra="forbid")
    id: UUID
    category: TimelineCategory
    event_code: str
    occurred_at: datetime
    plot_id: UUID
    crop_id: UUID | None = None
    reference_id: UUID
    data: dict[str, Any] = Field(default_factory=dict)


class TimelinePage(BaseModel):
    items: list[TimelineItem]
    limit: int
    offset: int
    has_more: bool


class TimelineQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crop_id: UUID | None = None
    categories: set[TimelineCategory] = Field(default_factory=set)
    date_from: datetime | None = None
    date_to: datetime | None = None
    limit: int = Field(default=30, ge=1, le=100)
    offset: int = Field(default=0, ge=0)

    @field_validator("date_from", "date_to")
    @classmethod
    def require_timezone(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("TIMELINE_TIMEZONE_REQUIRED")
        return value
