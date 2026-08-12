"""Reminder proposal, confirmation, and task-outcome contracts."""

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class FutureDueAtMixin(BaseModel):
    """Require unambiguous future reminder timestamps at the API boundary."""

    due_at: datetime

    @field_validator("due_at")
    @classmethod
    def validate_due_at(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("REMINDER_TIMEZONE_REQUIRED")
        normalized = value.astimezone(UTC)
        if normalized <= datetime.now(tz=UTC):
            raise ValueError("REMINDER_DUE_AT_MUST_BE_FUTURE")
        return normalized


class ReminderStatus(StrEnum):
    PENDING = "pending"
    DONE = "done"
    SKIPPED = "skipped"
    CANCELLED = "cancelled"


class ProposalCreate(FutureDueAtMixin):
    model_config = ConfigDict(extra="forbid")
    chat_id: UUID | None = None
    diagnosis_case_id: UUID | None = None
    plot_id: UUID | None = None
    crop_id: UUID | None = None
    title: Title
    recurrence_days: int | None = Field(default=None, ge=1, le=365)


class ProposalDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")
    accepted: bool


class ReminderCreate(FutureDueAtMixin):
    model_config = ConfigDict(extra="forbid")
    plot_id: UUID | None = None
    crop_id: UUID | None = None
    diagnosis_case_id: UUID | None = None
    title: Title
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=2000)] | None = None
    recurrence_days: int | None = Field(default=None, ge=1, le=365)


class ReminderAction(StrEnum):
    DONE = "done"
    SKIP = "skip"
    RESCHEDULE = "reschedule"
    CANCEL = "cancel"


class ReminderActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    action: ReminderAction
    due_at: datetime | None = None

    @model_validator(mode="after")
    def validate_reschedule(self) -> Self:
        if (self.action is ReminderAction.RESCHEDULE) != (self.due_at is not None):
            raise ValueError("REMINDER_RESCHEDULE_DATE_INVALID")
        if self.due_at is not None:
            if self.due_at.tzinfo is None or self.due_at.utcoffset() is None:
                raise ValueError("REMINDER_TIMEZONE_REQUIRED")
            self.due_at = self.due_at.astimezone(UTC)
            if self.due_at <= datetime.now(tz=UTC):
                raise ValueError("REMINDER_DUE_AT_MUST_BE_FUTURE")
        return self


class ProposalResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    chat_id: UUID | None
    diagnosis_case_id: UUID | None
    plot_id: UUID | None
    crop_id: UUID | None
    title: str
    due_at: datetime
    recurrence_days: int | None
    status: str
    created_at: datetime
    decided_at: datetime | None


class ReminderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    proposal_id: UUID | None
    chat_id: UUID | None
    diagnosis_case_id: UUID | None
    plot_id: UUID | None
    crop_id: UUID | None
    title: str
    notes: str | None
    due_at: datetime
    recurrence_days: int | None
    status: ReminderStatus
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class ProposalDecisionResponse(BaseModel):
    proposal: ProposalResponse
    reminder: ReminderResponse | None
