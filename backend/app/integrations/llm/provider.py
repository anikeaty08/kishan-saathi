"""Typed language-model provider contracts."""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.errors import ApplicationError


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
    """Safety-verifiable treatment detail; brands remain outside initial scope."""

    active_ingredient: str | None = Field(default=None, max_length=200)
    dosage: str | None = Field(default=None, max_length=300)
    application_method: str | None = Field(default=None, max_length=500)
    frequency: str | None = Field(default=None, max_length=300)
    safety_precautions: list[str] = Field(default_factory=list, max_length=8)
    consult_local_approved_guidance: bool = True

    @model_validator(mode="after")
    def require_safety_for_specific_treatment(self) -> "TreatmentGuidance":
        has_specifics = any(
            (self.active_ingredient, self.dosage, self.application_method, self.frequency)
        )
        if has_specifics and not self.safety_precautions:
            raise ValueError("TREATMENT_SAFETY_PRECAUTIONS_REQUIRED")
        if has_specifics and not self.consult_local_approved_guidance:
            raise ValueError("LOCAL_APPROVAL_CAVEAT_REQUIRED")
        return self


class AssistantReply(BaseModel):
    """Structured farmer-facing response from the LLM."""

    short_answer: str = Field(min_length=1, max_length=3000)
    details: str | None = Field(default=None, max_length=6000)
    follow_up_questions: list[str] = Field(default_factory=list, max_length=5)
    treatment: TreatmentGuidance | None = None
    reminder_proposal: ReminderProposalDraft | None = None


class MemoryCandidate(BaseModel):
    """One confirmed, scope-relevant fact safe to place in long-term memory."""

    text: str = Field(min_length=1, max_length=500)
    source_message_id: UUID
    evidence_quote: str = Field(min_length=1, max_length=500)


class MemoryExtraction(BaseModel):
    facts: list[MemoryCandidate] = Field(default_factory=list, max_length=20)


class GeneratedTitle(BaseModel):
    title: str = Field(min_length=1, max_length=150)


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


@dataclass(frozen=True, slots=True)
class LLMResult:
    reply: AssistantReply
    provider_response_id: str
    model: str


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

    async def close(self) -> None:
        return None
