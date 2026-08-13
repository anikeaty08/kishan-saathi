"""API and service contracts for multi-image diagnosis cases."""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.integrations.progression.provider import ProgressionImageQuality, ProgressionTrend
from app.modules.users.schemas import SupportedLanguage

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
    image_ids: list[UUID] = Field(default_factory=list)


class DiagnosisImagePredictionResponse(BaseModel):
    image_id: UUID
    predictions: list[PredictionResponse]


class DiagnosisCaseResponse(BaseModel):
    id: UUID
    title: str
    status: str
    plant_name: str | None
    farm_id: UUID | None
    plot_id: UUID | None
    crop_id: UUID | None
    image_count: int
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


class ProgressionComparisonRequest(BaseModel):
    """Select two timepoints, or omit both to compare the latest two."""

    model_config = ConfigDict(extra="forbid")

    earlier_assessment_id: UUID | None = None
    later_assessment_id: UUID | None = None
    response_language: SupportedLanguage = SupportedLanguage.ENGLISH

    @model_validator(mode="after")
    def validate_selection(self) -> Self:
        selected = self.earlier_assessment_id is not None
        if selected != (self.later_assessment_id is not None):
            raise ValueError("PROGRESSION_BOTH_ASSESSMENTS_REQUIRED")
        if selected and self.earlier_assessment_id == self.later_assessment_id:
            raise ValueError("PROGRESSION_DISTINCT_ASSESSMENTS_REQUIRED")
        return self


class ProgressionComparisonResponse(BaseModel):
    """Farmer-visible visual comparison, explicitly separate from diagnosis."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    case_id: UUID
    earlier_assessment_id: UUID
    later_assessment_id: UUID
    earlier_captured_at: datetime
    later_captured_at: datetime
    earlier_image_ids: list[UUID] = Field(min_length=1, max_length=6)
    later_image_ids: list[UUID] = Field(min_length=1, max_length=6)
    trend: ProgressionTrend
    confidence: float = Field(ge=0, le=1)
    summary: str
    evidence: list[str]
    limitations: list[str]
    image_quality: ProgressionImageQuality
    model_name: str
    generated_at: datetime
    scope: Literal["visible_symptom_progression_only"] = "visible_symptom_progression_only"
