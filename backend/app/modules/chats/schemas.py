"""Typed chat transport contracts."""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator


class ChatScope(StrEnum):
    GENERAL = "general"
    FARM = "farm"
    PLOT = "plot"
    SCAN = "scan"


class ChatCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    scope_type: ChatScope = ChatScope.GENERAL
    farm_id: UUID | None = None
    plot_id: UUID | None = None
    diagnosis_case_id: UUID | None = None

    @model_validator(mode="after")
    def validate_scope_shape(self) -> Self:
        if self.scope_type is ChatScope.GENERAL:
            valid = not any((self.farm_id, self.plot_id, self.diagnosis_case_id))
        elif self.scope_type is ChatScope.FARM:
            valid = self.farm_id is not None and not any(
                (self.plot_id, self.diagnosis_case_id)
            )
        elif self.scope_type is ChatScope.PLOT:
            valid = self.plot_id is not None and self.diagnosis_case_id is None
        else:
            valid = self.diagnosis_case_id is not None
        if not valid:
            raise ValueError("CHAT_SCOPE_INVALID")
        return self


class ChatUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)
    ] | None = None
    archived: bool | None = None

    @model_validator(mode="after")
    def require_change(self) -> Self:
        if not self.model_fields_set or any(
            getattr(self, field) is None for field in self.model_fields_set
        ):
            raise ValueError("CHAT_UPDATE_INVALID")
        return self


class ChatMessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    content: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=6000)
    ]


class ChatMessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    sequence: int
    role: str
    content: str
    created_at: datetime


class ChatResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    scope_type: ChatScope
    farm_id: UUID | None
    plot_id: UUID | None
    diagnosis_case_id: UUID | None
    title: str
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime


class ChatDetailResponse(ChatResponse):
    messages: list[ChatMessageResponse] = Field(default_factory=list)


class SendMessageResponse(BaseModel):
    user_message: ChatMessageResponse
    assistant_message: ChatMessageResponse
    reminder_proposal: str | None
