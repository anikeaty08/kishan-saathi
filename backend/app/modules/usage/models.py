"""Append-only model-provider usage records."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class AIUsageEvent(Base):
    """One provider workflow usage observation without farmer content."""

    __tablename__ = "ai_usage_events"
    __table_args__ = (
        Index("ix_ai_usage_farmer_created", "farmer_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="CASCADE"), index=True
    )
    operation: Mapped[str] = mapped_column(String(40), index=True)
    model: Mapped[str] = mapped_column(String(100), index=True)
    provider_response_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    request_count: Mapped[int] = mapped_column(Integer, default=0)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cached_input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cache_write_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    reasoning_tokens: Mapped[int] = mapped_column(Integer, default=0)
    total_tokens: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ProviderRateLimitBucket(Base):
    """Cross-replica per-farmer fixed-window reservation counter."""

    __tablename__ = "provider_rate_limit_buckets"
    __table_args__ = (
        UniqueConstraint(
            "farmer_id",
            "operation",
            "window_start",
            name="uq_provider_rate_limit_bucket",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="CASCADE"), index=True
    )
    operation: Mapped[str] = mapped_column(String(40), index=True)
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    request_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AuthRateLimitBucket(Base):
    """Cross-replica pre-authentication fixed-window reservation counter."""

    __tablename__ = "auth_rate_limit_buckets"
    __table_args__ = (
        UniqueConstraint(
            "subject_key",
            "window_start",
            name="uq_auth_rate_limit_bucket",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    subject_key: Mapped[UUID] = mapped_column(index=True)
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    request_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
