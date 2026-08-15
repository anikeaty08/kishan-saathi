"""Typed language-model provider contracts."""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.core.errors import ApplicationError
from app.integrations.llm.safety import reject_specific_treatment


class LLMTask(StrEnum):
    TITLE = "title"
    ROUTING = "routing"
    EXTRACTION = "extraction"
    ROUTINE_CHAT = "routine_chat"
    AGRICULTURAL_GUIDANCE = "agricultural_guidance"


class ReminderProposalDraft(BaseModel):
    """Typed, non-executing reminder suggestion produced by the agent."""

    title: str = Field(min_length=1, max_length=200)
    due_at: datetime
    recurrence_days: int | None = Field(default=None, ge=1, le=365)

    @field_validator("due_at")
    @classmethod
    def validate_future_aware_time(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("REMINDER_TIMEZONE_REQUIRED")
        normalized = value.astimezone(UTC)
        if normalized <= datetime.now(tz=UTC):
            raise ValueError("REMINDER_DUE_AT_MUST_BE_FUTURE")
        return normalized


class TreatmentGuidance(BaseModel):
    """General safety guidance until an authoritative local treatment source exists."""

    model_config = ConfigDict(extra="forbid")

    safety_precautions: list[str] = Field(default_factory=list, max_length=8)
    consult_local_approved_guidance: bool = True

    @field_validator("safety_precautions", mode="after")
    @classmethod
    def reject_prescriptive_precautions(cls, values: list[str]) -> list[str]:
        reject_specific_treatment(values)
        return values


class ReplyCertainty(StrEnum):
    CONFIRMED_CONTEXT = "confirmed_context"
    POSSIBLE = "possible"
    INSUFFICIENT_CONTEXT = "insufficient_context"
    INSUFFICIENT_IMAGE_QUALITY = "insufficient_image_quality"


class ReplyDisposition(StrEnum):
    """High-level response policy selected for one farmer turn."""

    IN_SCOPE = "in_scope"
    OUT_OF_SCOPE = "out_of_scope"


class AnswerSection(BaseModel):
    """One independently readable answer when a turn contains multiple questions."""

    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=2000)


class EvidenceSource(StrEnum):
    TRAINED_LEAF_CLASSIFIER = "trained_leaf_classifier"
    FARMER_MESSAGE = "farmer_message"
    TRUSTED_CONTEXT = "trusted_context"
    LINKED_WEATHER = "linked_weather"


class EvidenceRef(BaseModel):
    source: EvidenceSource
    summary: str = Field(min_length=1, max_length=500)


class RetakeAdvice(BaseModel):
    reason_codes: list[str] = Field(default_factory=list, max_length=6)
    instructions: list[str] = Field(default_factory=list, max_length=6)


class DiagnosisDiscussion(BaseModel):
    """A classifier-grounded disease reference; never a free model diagnosis."""

    assessment_id: UUID
    crop_name: str = Field(min_length=1, max_length=200)
    disease_name: str = Field(min_length=1, max_length=300)
    confidence_label: str = Field(min_length=1, max_length=50)


class AssistantReply(BaseModel):
    """Structured farmer-facing response from the LLM."""

    short_answer: str = Field(min_length=1, max_length=3000)
    disposition: ReplyDisposition = ReplyDisposition.IN_SCOPE
    answer_sections: list[AnswerSection] = Field(default_factory=list, max_length=6)
    details: str | None = Field(default=None, max_length=6000)
    explanation_points: list[str] = Field(default_factory=list, max_length=8)
    next_steps: list[str] = Field(default_factory=list, max_length=8)
    follow_up_questions: list[str] = Field(default_factory=list, max_length=5)
    certainty: ReplyCertainty = ReplyCertainty.POSSIBLE
    evidence_used: list[EvidenceRef] = Field(default_factory=list, max_length=10)
    diagnosis_discussion: DiagnosisDiscussion | None = None
    retake_advice: RetakeAdvice | None = None
    general_precautions: list[str] = Field(default_factory=list, max_length=8)
    consult_local_expert: bool = False
    treatment: TreatmentGuidance | None = None
    reminder_proposal: ReminderProposalDraft | None = None

    @model_validator(mode="after")
    def reject_prescriptive_visible_text(self) -> "AssistantReply":
        reject_specific_treatment(self)
        if self.certainty is ReplyCertainty.INSUFFICIENT_IMAGE_QUALITY and not self.retake_advice:
            raise ValueError("RETAKE_ADVICE_REQUIRED")
        if self.disposition is ReplyDisposition.OUT_OF_SCOPE:
            if any(
                (
                    self.answer_sections,
                    self.explanation_points,
                    self.next_steps,
                    self.follow_up_questions,
                    self.evidence_used,
                    self.diagnosis_discussion,
                    self.retake_advice,
                    self.general_precautions,
                    self.treatment,
                    self.reminder_proposal,
                )
            ):
                raise ValueError("OUT_OF_SCOPE_REPLY_MUST_BE_REDIRECT_ONLY")
            if self.consult_local_expert:
                raise ValueError("OUT_OF_SCOPE_REPLY_MUST_BE_REDIRECT_ONLY")
        return self


class MemoryCandidate(BaseModel):
    """One confirmed, scope-relevant fact safe to place in long-term memory."""

    text: str = Field(min_length=1, max_length=500)
    source_message_id: UUID
    evidence_quote: str = Field(min_length=1, max_length=500)


class MemoryExtraction(BaseModel):
    facts: list[MemoryCandidate] = Field(default_factory=list, max_length=20)


class GeneratedTitle(BaseModel):
    title: str = Field(min_length=1, max_length=150)


class ChatRiskClassification(BaseModel):
    """Typed classification used only to choose an approved model policy."""

    requires_primary_model: bool
    is_agricultural: bool = True
    reason_code: "ChatRiskReason"


class ChatRiskReason(StrEnum):
    ROUTINE = "routine"
    SCAN_CONTEXT = "scan_context"
    DIAGNOSIS_OR_SYMPTOMS = "diagnosis_or_symptoms"
    TREATMENT_SAFETY = "treatment_safety"
    FARM_OR_PLOT_CONTEXT = "farm_or_plot_context"
    URGENT_OR_AMBIGUOUS = "urgent_or_ambiguous"
    UNCERTAIN = "uncertain"
    OUT_OF_SCOPE = "out_of_scope"


@dataclass(frozen=True, slots=True)
class LLMTool:
    """A narrowly scoped backend function the provider may let the model request."""

    name: str
    description: str
    execute: Callable[[], Awaitable[str]]


@dataclass(frozen=True, slots=True)
class LLMRequest:
    task: LLMTask
    instructions: str
    input_text: str
    farmer_id: UUID
    tools: tuple[LLMTool, ...] = ()
    allow_diagnosis: bool = False
    required_disposition: ReplyDisposition | None = None


@dataclass(frozen=True, slots=True)
class LLMResult:
    reply: AssistantReply
    provider_response_id: str
    model: str
    policy_reviewed: bool


@dataclass(frozen=True, slots=True)
class MemoryExtractionRequest:
    transcript: str
    target_scope: str
    target_name: str
    farmer_id: UUID


class LLMProvider(Protocol):
    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult: ...

    async def extract_memories(
        self, request: MemoryExtractionRequest, *, model: str
    ) -> MemoryExtraction: ...

    async def generate_title(
        self, *, content: str, language: str, farmer_id: UUID, model: str
    ) -> GeneratedTitle: ...

    async def classify_chat_risk(
        self, *, content: str, farmer_id: UUID, model: str
    ) -> ChatRiskClassification: ...

    async def close(self) -> None: ...


class UnavailableLLMProvider:
    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        del request, model
        raise ApplicationError(code="LLM_NOT_CONFIGURED", status_code=503)

    async def extract_memories(
        self, request: MemoryExtractionRequest, *, model: str
    ) -> MemoryExtraction:
        del request, model
        raise ApplicationError(code="LLM_NOT_CONFIGURED", status_code=503)

    async def generate_title(
        self, *, content: str, language: str, farmer_id: UUID, model: str
    ) -> GeneratedTitle:
        del content, language, farmer_id, model
        raise ApplicationError(code="LLM_NOT_CONFIGURED", status_code=503)

    async def classify_chat_risk(
        self, *, content: str, farmer_id: UUID, model: str
    ) -> ChatRiskClassification:
        del content, farmer_id, model
        raise ApplicationError(code="LLM_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
