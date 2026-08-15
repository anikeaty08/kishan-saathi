"""Pydantic farmer-profile request and response contracts."""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints, model_validator


class SupportedLanguage(StrEnum):
    """English plus all 22 languages in India's Eighth Schedule."""

    ASSAMESE = "as"
    BENGALI = "bn"
    BODO = "brx"
    DOGRI = "doi"
    ENGLISH = "en"
    GUJARATI = "gu"
    HINDI = "hi"
    KANNADA = "kn"
    KASHMIRI = "ks"
    KONKANI = "kok"
    MAITHILI = "mai"
    MALAYALAM = "ml"
    MANIPURI = "mni"
    MARATHI = "mr"
    NEPALI = "ne"
    ODIA = "or"
    PUNJABI = "pa"
    SANSKRIT = "sa"
    SANTALI = "sat"
    SINDHI = "sd"
    TAMIL = "ta"
    TELUGU = "te"
    URDU = "ur"


class AreaUnit(StrEnum):
    """Farmer-selectable area display unit."""

    ACRE = "acre"
    HECTARE = "hectare"


FarmerName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class FarmerProfileUpdate(BaseModel):
    """Editable farmer preferences; email remains owned by Cognito."""

    model_config = ConfigDict(extra="forbid")

    name: FarmerName | None = None
    preferred_language: SupportedLanguage | None = None
    area_unit: AreaUnit | None = None
    notifications_enabled: bool | None = None

    @model_validator(mode="after")
    def require_at_least_one_change(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("PROFILE_UPDATE_EMPTY")
        if any(getattr(self, field) is None for field in self.model_fields_set):
            raise ValueError("PROFILE_FIELD_NULL")
        return self


class FarmerProfileResponse(BaseModel):
    """Authenticated farmer's persisted profile."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    email_verified: bool
    name: str | None
    preferred_language: SupportedLanguage | None
    area_unit: AreaUnit
    notifications_enabled: bool
    onboarding_complete: bool
    created_at: datetime
    updated_at: datetime
