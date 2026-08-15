"""Voice API response contracts."""

from pydantic import BaseModel, ConfigDict, Field


class VoiceTranscriptionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    transcript: str = Field(min_length=1, max_length=12000)
