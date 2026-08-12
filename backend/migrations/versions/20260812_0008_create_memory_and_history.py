"""Create canonical scoped memory and immutable reminder history.

Revision ID: 20260812_0008
Revises: 20260812_0007
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260812_0008"
down_revision: str | None = "20260812_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "chat_memory_connections",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("chat_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farm_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("plot_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_chat_memory_connections_scope",
        ),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("chat_id", name="uq_chat_memory_connections_chat"),
    )
    for column in ("farmer_id", "chat_id", "farm_id", "plot_id"):
        op.create_index(
            f"ix_chat_memory_connections_{column}",
            "chat_memory_connections",
            [column],
        )

    op.create_table(
        "scoped_memory_facts",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farm_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("plot_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("source_chat_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("source_message_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("evidence_quote", sa.Text(), nullable=True),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("normalized_text", sa.String(length=500), nullable=False),
        sa.Column("provider_memory_id", sa.String(length=255), nullable=True),
        sa.Column(
            "index_status", sa.String(length=16), server_default="pending", nullable=False
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_scoped_memory_facts_scope",
        ),
        sa.CheckConstraint(
            "index_status IN ('pending', 'indexed', 'failed', 'deleting', 'delete_failed')",
            name="ck_scoped_memory_facts_index_status",
        ),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["source_chat_id"], ["chat_sessions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["source_message_id"], ["chat_messages.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "farmer_id",
        "farm_id",
        "plot_id",
        "source_chat_id",
        "source_message_id",
        "index_status",
    ):
        op.create_index(
            f"ix_scoped_memory_facts_{column}", "scoped_memory_facts", [column]
        )
    op.create_index(
        "uq_scoped_memory_facts_farm_content",
        "scoped_memory_facts",
        ["farmer_id", "farm_id", "normalized_text"],
        unique=True,
        postgresql_where=sa.text("farm_id IS NOT NULL"),
    )
    op.create_index(
        "uq_scoped_memory_facts_plot_content",
        "scoped_memory_facts",
        ["farmer_id", "plot_id", "normalized_text"],
        unique=True,
        postgresql_where=sa.text("plot_id IS NOT NULL"),
    )

    op.add_column(
        "reminders",
        sa.Column("series_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.execute("UPDATE reminders SET series_id = id WHERE series_id IS NULL")
    op.alter_column("reminders", "series_id", nullable=False)
    op.add_column(
        "reminders",
        sa.Column("parent_reminder_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_reminders_parent_reminder_id",
        "reminders",
        "reminders",
        ["parent_reminder_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_reminders_series_id", "reminders", ["series_id"])
    op.create_index(
        "ix_reminders_parent_reminder_id", "reminders", ["parent_reminder_id"]
    )

    op.create_table(
        "reminder_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reminder_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("series_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("chat_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("diagnosis_case_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("plot_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("crop_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("event_type", sa.String(length=16), nullable=False),
        sa.Column("previous_due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "occurred_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "event_type IN ('scheduled', 'done', 'skipped', 'rescheduled', 'cancelled')",
            name="ck_reminder_events_type",
        ),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["diagnosis_case_id"], ["diagnosis_cases.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["reminder_id"], ["reminders.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "farmer_id",
        "reminder_id",
        "series_id",
        "chat_id",
        "diagnosis_case_id",
        "plot_id",
        "crop_id",
        "event_type",
        "occurred_at",
    ):
        op.create_index(f"ix_reminder_events_{column}", "reminder_events", [column])

    op.execute(
        """
        INSERT INTO reminder_events (
            id, farmer_id, reminder_id, series_id, chat_id, diagnosis_case_id,
            plot_id, crop_id, event_type, due_at, occurred_at
        )
        SELECT gen_random_uuid(), farmer_id, id, series_id, chat_id, diagnosis_case_id,
               plot_id, crop_id, 'scheduled', due_at, created_at
        FROM reminders
        """
    )
    op.execute(
        """
        INSERT INTO reminder_events (
            id, farmer_id, reminder_id, series_id, chat_id, diagnosis_case_id,
            plot_id, crop_id, event_type, due_at, occurred_at
        )
        SELECT gen_random_uuid(), farmer_id, id, series_id, chat_id, diagnosis_case_id,
               plot_id, crop_id, status, due_at, COALESCE(completed_at, updated_at)
        FROM reminders
        WHERE status IN ('done', 'skipped', 'cancelled')
        """
    )


def downgrade() -> None:
    op.drop_table("reminder_events")
    op.drop_index("ix_reminders_parent_reminder_id", table_name="reminders")
    op.drop_index("ix_reminders_series_id", table_name="reminders")
    op.drop_constraint(
        "fk_reminders_parent_reminder_id", "reminders", type_="foreignkey"
    )
    op.drop_column("reminders", "parent_reminder_id")
    op.drop_column("reminders", "series_id")
    op.drop_table("scoped_memory_facts")
    op.drop_table("chat_memory_connections")
