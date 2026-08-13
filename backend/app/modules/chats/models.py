"""Persistence models for isolated chat sessions and messages."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class ChatSession(Base):
    """One independent conversation with an explicit immutable scope type."""

    __tablename__ = "chat_sessions"
    __table_args__ = (
        CheckConstraint(
            "scope_type IN ('general', 'farm', 'plot', 'scan')",
            name="ck_chat_sessions_scope_type",
        ),
        CheckConstraint(
            "(scope_type = 'general' AND farm_id IS NULL AND plot_id IS NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'farm' AND farm_id IS NOT NULL AND plot_id IS NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'plot' AND plot_id IS NOT NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'scan' AND diagnosis_case_id IS NOT NULL)",
            name="ck_chat_sessions_scope_shape",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    scope_type: Mapped[str] = mapped_column(String(16), index=True)
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    diagnosis_case_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(150), default="New conversation")
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ChatMessage(Base):
    """Persisted user or assistant message within one owned chat session."""

    __tablename__ = "chat_messages"
    __table_args__ = (
        UniqueConstraint("chat_id", "sequence", name="uq_chat_messages_sequence"),
        CheckConstraint("role IN ('user', 'assistant')", name="ck_chat_messages_role"),
        CheckConstraint("sequence >= 1", name="ck_chat_messages_sequence_positive"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    sequence: Mapped[int] = mapped_column(Integer)
    role: Mapped[str] = mapped_column(String(16))
    content: Mapped[str] = mapped_column(Text)
    model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    provider_response_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    structured_content: Mapped[dict[str, object] | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ChatSendOperation(Base):
    """Completed idempotent message send, scoped to one farmer and chat."""

    __tablename__ = "chat_send_operations"
    __table_args__ = (
        UniqueConstraint(
            "farmer_id",
            "chat_id",
            "idempotency_key",
            name="uq_chat_send_operations_key",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    idempotency_key: Mapped[str] = mapped_column(String(128))
    request_hash: Mapped[str] = mapped_column(String(64))
    response: Mapped[dict[str, object]] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ChatTurn(Base):
    """Durable queued farmer turn processed in strict per-chat order."""

    __tablename__ = "chat_turns"
    __table_args__ = (
        UniqueConstraint(
            "farmer_id",
            "chat_id",
            "idempotency_key",
            name="uq_chat_turns_key",
        ),
        UniqueConstraint("chat_id", "sequence", name="uq_chat_turns_sequence"),
        CheckConstraint(
            "status IN ('queued', 'processing', 'completed', 'failed')",
            name="ck_chat_turns_status",
        ),
        Index(
            "ix_chat_turns_claim",
            "status",
            "next_attempt_at",
            "created_at",
            postgresql_where=text("status = 'queued'"),
            sqlite_where=text("status = 'queued'"),
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="CASCADE"), index=True
    )
    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    idempotency_key: Mapped[str] = mapped_column(String(128))
    request_hash: Mapped[str] = mapped_column(String(64))
    sequence: Mapped[int] = mapped_column(Integer)
    content: Mapped[str] = mapped_column(Text)
    preferred_language: Mapped[str | None] = mapped_column(String(8), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="queued", index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    response: Mapped[dict[str, object] | None] = mapped_column(JSON, nullable=True)
    error_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    next_attempt_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    lease_token: Mapped[UUID | None] = mapped_column(nullable=True, index=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
