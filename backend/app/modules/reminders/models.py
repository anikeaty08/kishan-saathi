"""Persistence models for reminder proposals and in-app tasks."""

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


class ReminderProposal(Base):
    """AI or app proposal that cannot execute before explicit confirmation."""

    __tablename__ = "reminder_proposals"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'accepted', 'declined', 'expired')",
            name="ck_reminder_proposals_status",
        ),
        CheckConstraint(
            "recurrence_days IS NULL OR recurrence_days >= 1",
            name="ck_reminder_proposals_recurrence",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    chat_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=True, index=True
    )
    diagnosis_case_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="CASCADE"), nullable=True, index=True
    )
    crop_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("crops.id", ondelete="CASCADE"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    recurrence_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Reminder(Base):
    """Confirmed one-time or recurring in-app task."""

    __tablename__ = "reminders"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'done', 'skipped', 'cancelled')",
            name="ck_reminders_status",
        ),
        CheckConstraint(
            "recurrence_days IS NULL OR recurrence_days >= 1",
            name="ck_reminders_recurrence",
        ),
        UniqueConstraint("proposal_id", name="uq_reminders_proposal_id"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    series_id: Mapped[UUID] = mapped_column(default=uuid4, index=True)
    parent_reminder_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("reminders.id", ondelete="SET NULL"), nullable=True, index=True
    )
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    proposal_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("reminder_proposals.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    chat_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    diagnosis_case_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    crop_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("crops.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    recurrence_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ReminderEvent(Base):
    """Immutable reminder schedule and farmer-decision history."""

    __tablename__ = "reminder_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('scheduled', 'done', 'skipped', 'rescheduled', 'cancelled')",
            name="ck_reminder_events_type",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    reminder_id: Mapped[UUID] = mapped_column(
        ForeignKey("reminders.id", ondelete="CASCADE"), index=True
    )
    series_id: Mapped[UUID] = mapped_column(index=True)
    chat_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    diagnosis_case_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    crop_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("crops.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    event_type: Mapped[str] = mapped_column(String(16), index=True)
    previous_due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
