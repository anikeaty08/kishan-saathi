"""Typed contracts for visual change comparison across diagnosis timepoints."""

import re
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.core.errors import ApplicationError


def _reject_out_of_scope_language(text: str) -> None:
    """Reject diagnosis authority and common prescriptive forms."""

    diagnosis = re.compile(
        r"\b(?:diagnos(?:is|e|ed|tic)|disease|pathogen|fungal|bacterial|viral|"
        r"blight|mildew|canker|mosaic\s+virus)\b",
        flags=re.IGNORECASE,
    )
    treatment = re.compile(
        r"(?:\b\d+(?:\.\d+)?\s*(?:mg|g|kg|ml|l)\s*(?:/|per)\s*"
        r"(?:l|lit(?:re|er)s?|kg|acre|hectare)\b|"
        r"\bevery\s+\d+\s*(?:hour|day|week)s?\b|"
        r"\b(?:spray|apply|drench|inject|mix)\s+\d)",
        flags=re.IGNORECASE,
    )
    if diagnosis.search(text):
        raise ValueError("PROGRESSION_DIAGNOSIS_LANGUAGE_FORBIDDEN")
    if treatment.search(text):
        raise ValueError("PROGRESSION_TREATMENT_GUIDANCE_FORBIDDEN")


class ProgressionTrend(StrEnum):
    """Allowed visual-change outcomes; deliberately not disease labels."""

    IMPROVING = "improving"
    WORSENING = "worsening"
    UNCHANGED = "unchanged"
    UNCLEAR = "unclear"


class ProgressionImageQuality(BaseModel):
    """Provider assessment of whether the two image groups are comparable."""

    model_config = ConfigDict(extra="forbid")

    sufficient_for_comparison: bool
    earlier_issues: list[str] = Field(default_factory=list, max_length=6)
    later_issues: list[str] = Field(default_factory=list, max_length=6)
    retake_guidance: list[str] = Field(default_factory=list, max_length=6)

    @field_validator("earlier_issues", "later_issues", "retake_guidance")
    @classmethod
    def enforce_scope(cls, value: list[str]) -> list[str]:
        _reject_out_of_scope_language(" ".join(value))
        return value


class ProgressionAnalysis(BaseModel):
    """Strict provider output containing observations, never a diagnosis."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    trend: ProgressionTrend
    confidence: float = Field(ge=0, le=1)
    summary: str = Field(min_length=1, max_length=1200)
    evidence: list[str] = Field(min_length=1, max_length=8)
    limitations: list[str] = Field(default_factory=list, max_length=8)
    image_quality: ProgressionImageQuality

    @field_validator("summary", "evidence", "limitations")
    @classmethod
    def reject_prescriptive_treatment_language(cls, value: str | list[str]) -> str | list[str]:
        """Block diagnosis authority or treatment if a provider ignores its scope."""

        text = value if isinstance(value, str) else " ".join(value)
        _reject_out_of_scope_language(text)
        return value

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
class ProgressionRequest:
    """Two ordered image groups from one already owner-authorized case."""

    farmer_id: UUID
    earlier_images: tuple[ProgressionImage, ...]
    later_images: tuple[ProgressionImage, ...]
    response_language: str


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
