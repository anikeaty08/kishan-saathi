"""Scoped-memory API contracts."""

from datetime import datetime
from enum import StrEnum
from typing import Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, model_validator


class MemoryConnectionTarget(StrEnum):
    FARM = "farm"
    PLOT = "plot"


class ChatMemoryConnectionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    target_type: MemoryConnectionTarget
    farm_id: UUID | None = None
    plot_id: UUID | None = None

    @model_validator(mode="after")
    def validate_target(self) -> Self:
        valid = (
            self.target_type is MemoryConnectionTarget.FARM
            and self.farm_id is not None
            and self.plot_id is None
        ) or (
            self.target_type is MemoryConnectionTarget.PLOT
            and self.plot_id is not None
            and self.farm_id is None
        )
        if not valid:
            raise ValueError("MEMORY_CONNECTION_SCOPE_INVALID")
        return self


class MemoryFactResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    farm_id: UUID | None
    plot_id: UUID | None
    source_chat_id: UUID | None
    source_message_id: UUID | None
    evidence_quote: str | None
    text: str
    index_status: str
    created_at: datetime


class ChatMemoryConnectionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    chat_id: UUID
    farm_id: UUID | None
    plot_id: UUID | None
    created_at: datetime
    memories: list[MemoryFactResponse]
