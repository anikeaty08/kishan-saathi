"""Typed language-model provider contracts."""

from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol
from uuid import UUID

from pydantic import BaseModel, Field

from app.core.errors import ApplicationError


class LLMTask(StrEnum):
    TITLE = "title"
    ROUTING = "routing"
    EXTRACTION = "extraction"
    ROUTINE_CHAT = "routine_chat"
    AGRICULTURAL_GUIDANCE = "agricultural_guidance"


class AssistantReply(BaseModel):
    """Structured farmer-facing response from the LLM."""

    short_answer: str = Field(min_length=1, max_length=3000)
    details: str | None = Field(default=None, max_length=6000)
    follow_up_questions: list[str] = Field(default_factory=list, max_length=5)
    reminder_proposal: str | None = Field(default=None, max_length=300)


@dataclass(frozen=True, slots=True)
class LLMRequest:
    task: LLMTask
    instructions: str
    input_text: str
    farmer_id: UUID


@dataclass(frozen=True, slots=True)
class LLMResult:
    reply: AssistantReply
    provider_response_id: str
    model: str


class LLMProvider(Protocol):
    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult: ...

    async def close(self) -> None: ...


class UnavailableLLMProvider:
    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        del request, model
        raise ApplicationError(code="LLM_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
