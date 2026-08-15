"""Typed contracts for visual change comparison across diagnosis timepoints."""

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.core.errors import ApplicationError


class ProgressionTrend(StrEnum):
    """Allowed visual-change outcomes; deliberately not disease labels."""

    IMPROVING = "improving"
    WORSENING = "worsening"
    UNCHANGED = "unchanged"
    UNCLEAR = "unclear"


class ProgressionEvidenceCode(StrEnum):
    AFFECTED_AREA_REDUCED = "affected_area_reduced"
    AFFECTED_AREA_INCREASED = "affected_area_increased"
    AFFECTED_AREA_SIMILAR = "affected_area_similar"
    YELLOWING_REDUCED = "yellowing_reduced"
    YELLOWING_INCREASED = "yellowing_increased"
    BROWNING_REDUCED = "browning_reduced"
    BROWNING_INCREASED = "browning_increased"
    CURLING_REDUCED = "curling_reduced"
    CURLING_INCREASED = "curling_increased"
    WILTING_REDUCED = "wilting_reduced"
    WILTING_INCREASED = "wilting_increased"
    NO_RELIABLE_VISIBLE_DIFFERENCE = "no_reliable_visible_difference"


class ProgressionLimitationCode(StrEnum):
    DIFFERENT_LIGHTING = "different_lighting"
    DIFFERENT_VIEWPOINT = "different_viewpoint"
    DIFFERENT_ZOOM = "different_zoom"
    DIFFERENT_LEAF = "different_leaf"
    DIFFERENT_BACKGROUND = "different_background"
    EARLIER_IMAGE_QUALITY = "earlier_image_quality"
    LATER_IMAGE_QUALITY = "later_image_quality"
    TOO_LITTLE_VISIBLE_EVIDENCE = "too_little_visible_evidence"


class ProgressionRecommendationCode(StrEnum):
    MONITOR_SAME_LEAF = "monitor_same_leaf"
    RETAKE_SAME_ANGLE = "retake_same_angle"
    RETAKE_SAME_LIGHTING = "retake_same_lighting"
    RETAKE_FULL_PLANT_AND_CLOSE_LEAF = "retake_full_plant_and_close_leaf"
    KEEP_FOLIAGE_DRY = "keep_foliage_dry"
    USE_CLEAN_HANDS_AND_TOOLS = "use_clean_hands_and_tools"
    CONSULT_LOCAL_EXPERT_IF_WORSENING = "consult_local_expert_if_worsening"


class ProgressionImageQuality(BaseModel):
    """Provider assessment of whether the two image groups are comparable."""

    model_config = ConfigDict(extra="forbid")

    sufficient_for_comparison: bool
    earlier_issues: list[ProgressionLimitationCode] = Field(default_factory=list, max_length=6)
    later_issues: list[ProgressionLimitationCode] = Field(default_factory=list, max_length=6)
    retake_guidance: list[ProgressionRecommendationCode] = Field(default_factory=list, max_length=6)


class ProgressionAnalysis(BaseModel):
    """Strict provider output containing observations and general next steps."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    trend: ProgressionTrend
    confidence: float = Field(ge=0, le=1)
    evidence: list[ProgressionEvidenceCode] = Field(min_length=1, max_length=8)
    limitations: list[ProgressionLimitationCode] = Field(default_factory=list, max_length=8)
    recommendations: list[ProgressionRecommendationCode] = Field(default_factory=list, max_length=8)
    image_quality: ProgressionImageQuality

    @model_validator(mode="after")
    def unclear_when_images_are_not_comparable(self) -> "ProgressionAnalysis":
        if (
            not self.image_quality.sufficient_for_comparison
            and self.trend is not ProgressionTrend.UNCLEAR
        ):
            raise ValueError("PROGRESSION_UNUSABLE_IMAGES_REQUIRE_UNCLEAR_TREND")
        return self


@dataclass(frozen=True, slots=True)
class ProgressionImage:
    """One sanitized JPEG and its trusted server metadata."""

    image_id: UUID
    content: bytes
    captured_at: datetime


@dataclass(frozen=True, slots=True)
class ProgressionDiagnosisContext:
    """Backend-owned classifier result that the visual comparison may reference."""

    assessment_id: UUID
    crop_name: str
    disease_name: str
    confidence_label: str


@dataclass(frozen=True, slots=True)
class ProgressionRequest:
    """Two ordered image groups from one already owner-authorized case."""

    farmer_id: UUID
    earlier_images: tuple[ProgressionImage, ...]
    later_images: tuple[ProgressionImage, ...]
    response_language: str
    classifier_context: ProgressionDiagnosisContext | None = None


@dataclass(frozen=True, slots=True)
class ProgressionResult:
    analysis: ProgressionAnalysis
    provider_response_id: str
    model: str


class ProgressionProvider(Protocol):
    async def compare(self, request: ProgressionRequest) -> ProgressionResult: ...

    async def close(self) -> None: ...


class UnavailableProgressionProvider:
    async def compare(self, request: ProgressionRequest) -> ProgressionResult:
        del request
        raise ApplicationError(code="PROGRESSION_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
