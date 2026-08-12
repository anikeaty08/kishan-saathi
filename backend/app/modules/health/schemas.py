"""Pydantic health response contracts."""

from enum import StrEnum

from pydantic import BaseModel, Field


class HealthStatus(StrEnum):
    """Overall process health state."""

    OK = "ok"
    NOT_READY = "not_ready"


class DependencyStatus(StrEnum):
    """Health state for an individual required dependency."""

    UP = "up"
    DOWN = "down"


class DependencyCheck(BaseModel):
    """Public dependency status without sensitive connection details."""

    status: DependencyStatus


class HealthResponse(BaseModel):
    """Stable liveness and readiness response body."""

    status: HealthStatus
    service: str
    version: str
    checks: dict[str, DependencyCheck] = Field(default_factory=dict)
