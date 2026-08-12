"""Typed report approval and public snapshot contracts."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator


class ReportApproval(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=255)
    ] | None = None
    include_alternatives: bool = False
    include_feedback: bool = False
    include_plot_name: bool = False
    include_plot_location: bool = False
    image_ids: list[UUID] = Field(default_factory=list, max_length=10)
    expires_at: datetime

    @field_validator("expires_at")
    @classmethod
    def timezone_required(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("REPORT_EXPIRY_TIMEZONE_REQUIRED")
        return value


class ReportImageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    source_image_id: UUID | None
    size_bytes: int


class DiagnosisReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    diagnosis_case_id: UUID
    title: str
    snapshot: dict[str, object]
    approved_fields: list[str]
    status: str
    expires_at: datetime
    created_at: datetime
    revoked_at: datetime | None
    images: list[ReportImageResponse]


class CreatedReportResponse(DiagnosisReportResponse):
    share_token: str


class PublicDiagnosisReport(BaseModel):
    id: UUID
    title: str
    snapshot: dict[str, object]
    approved_fields: list[str]
    expires_at: datetime
    created_at: datetime
    images: list[ReportImageResponse]
