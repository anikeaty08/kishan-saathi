"""Typed public authentication request and response contracts."""

from pydantic import BaseModel, ConfigDict, EmailStr, Field, SecretStr, field_validator


class EmailRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr


class PasswordRequest(EmailRequest):
    password: SecretStr = Field(min_length=8, max_length=256)


class SignUpRequest(PasswordRequest):
    name: str = Field(min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        normalized = " ".join(value.split())
        if not normalized:
            raise ValueError("name must not be blank")
        return normalized


class ConfirmationRequest(EmailRequest):
    code: SecretStr = Field(min_length=4, max_length=16)


class PasswordResetConfirmationRequest(ConfirmationRequest):
    new_password: SecretStr = Field(min_length=8, max_length=256)


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    refresh_token: SecretStr = Field(min_length=20, max_length=8192)


class SignUpResponse(BaseModel):
    confirmed: bool


class AuthTokensResponse(BaseModel):
    access_token: str
    refresh_token: str
    id_token: str | None
    expires_in: int = Field(gt=0, le=86400)
