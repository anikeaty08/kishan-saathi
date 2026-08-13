"""Canonical scoped-memory records and chat connections."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
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


class ChatMemoryConnection(Base):
    """A general chat connected once to one farmer-owned farm or plot."""

    __tablename__ = "chat_memory_connections"
    __table_args__ = (
        UniqueConstraint("chat_id", name="uq_chat_memory_connections_chat"),
        CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_chat_memory_connections_scope",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="CASCADE"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="CASCADE"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ScopedMemoryFact(Base):
    """Reviewable source-of-truth fact, optionally indexed by Mem0."""

    __tablename__ = "scoped_memory_facts"
    __table_args__ = (
        CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_scoped_memory_facts_scope",
        ),
        CheckConstraint(
            "index_status IN ('pending', 'indexed', 'failed', 'deleting', 'delete_failed')",
            name="ck_scoped_memory_facts_index_status",
        ),
        Index(
            "uq_scoped_memory_facts_farm_content",
            "farmer_id",
            "farm_id",
            "normalized_text",
            unique=True,
            postgresql_where=text("farm_id IS NOT NULL"),
            sqlite_where=text("farm_id IS NOT NULL"),
        ),
        Index(
            "uq_scoped_memory_facts_plot_content",
            "farmer_id",
            "plot_id",
            "normalized_text",
            unique=True,
            postgresql_where=text("plot_id IS NOT NULL"),
            sqlite_where=text("plot_id IS NOT NULL"),
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="CASCADE"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="CASCADE"), nullable=True, index=True
    )
    source_chat_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source_message_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat_messages.id", ondelete="SET NULL"), nullable=True, index=True
    )
    evidence_quote: Mapped[str | None] = mapped_column(Text, nullable=True)
    text: Mapped[str] = mapped_column(Text)
    normalized_text: Mapped[str] = mapped_column(String(500))
    provider_memory_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    index_status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class MemoryCaptureJob(Base):
    """Durable automatic extraction requested in the chat transaction."""

    __tablename__ = "memory_capture_jobs"
    __table_args__ = (
        UniqueConstraint("source_message_id", name="uq_memory_capture_jobs_source_message"),
        CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_memory_capture_jobs_scope",
        ),
        CheckConstraint(
            "status IN ('pending', 'processing', 'dead')",
            name="ck_memory_capture_jobs_status",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="CASCADE"), index=True
    )
    chat_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    source_message_id: Mapped[UUID] = mapped_column(
        ForeignKey("chat_messages.id", ondelete="CASCADE"), index=True
    )
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="CASCADE"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="CASCADE"), nullable=True, index=True
    )
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    last_error_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    next_attempt_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    lease_token: Mapped[UUID | None] = mapped_column(nullable=True, index=True)
    dead_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
