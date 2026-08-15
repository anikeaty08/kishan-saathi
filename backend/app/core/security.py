"""Shared authenticated-principal and authorization contracts."""

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True, slots=True)
class AuthenticatedPrincipal:
    """Trusted identity extracted from a verified Cognito access token."""

    subject: str
    username: str
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class AuthContext:
    """Per-request authorization context including the original bearer token."""

    principal: AuthenticatedPrincipal
    access_token: str


@dataclass(frozen=True, slots=True)
class ExternalIdentity:
    """Canonical Cognito attributes used to provision a local profile."""

    subject: str
    username: str
    email: str
    email_verified: bool
    name: str | None = None
