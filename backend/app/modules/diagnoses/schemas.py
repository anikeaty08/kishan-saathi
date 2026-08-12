"""API and service contracts for multi-image diagnosis cases."""

from datetime import datetime
from enum import StrEnum
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

PlantName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class ConfidenceLabel(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class IncomingImage(BaseModel):
    """Validated transport data passed from router to service."""

    model_config = ConfigDict(arbitrary_types_allowed=True)
    content: bytes
    captured_or_uploaded_at: datetime


class DiagnosisLink(BaseModel):
    model_config = ConfigDict(extra="forbid")
    farm_id: UUID | None = None
    plot_id: UUID | None = None
    crop_id: UUID | None = None


class DiagnosisFeedbackUpsert(BaseModel):
    model_config = ConfigDict(extra="forbid")
    is_incorrect: bool
    corrected_crop: PlantName | None = None
    corrected_disease: (
        Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)] | None
    ) = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=2000)] | None = None


class PredictionResponse(BaseModel):
    crop_name: str
    disease_name: str
    rank: int = Field(ge=1)


class DiagnosisImageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    captured_or_uploaded_at: datetime
    width: int
    height: int
    quality_score: float | None
    quality_flags: list[str]


class AssessmentResponse(BaseModel):
    id: UUID
    predicted_crop: str
    primary_disease: str
    confidence_label: ConfidenceLabel
    alternatives: list[PredictionResponse]
    is_active: bool
    model_name: str
    model_version: str
    created_at: datetime


class AssessmentHistoryResponse(AssessmentResponse):
    image_predictions: dict[UUID, list[PredictionResponse]] = Field(default_factory=dict)


class DiagnosisCaseResponse(BaseModel):
    id: UUID
    title: str
    status: str
    plant_name: str | None
    farm_id: UUID | None
    plot_id: UUID | None
    crop_id: UUID | None
    images: list[DiagnosisImageResponse]
    active_assessment: AssessmentResponse | None
    retake_recommended: bool
    created_at: datetime
    updated_at: datetime


class DiagnosisFeedbackResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    case_id: UUID
    is_incorrect: bool
    corrected_crop: str | None
    corrected_disease: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime
