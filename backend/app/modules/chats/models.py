"""Persistence models for isolated chat sessions and messages."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
