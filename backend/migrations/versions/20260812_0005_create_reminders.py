"""Create reminder proposals and confirmed in-app tasks.

Revision ID: 20260812_0005
Revises: 20260812_0004
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0005"
down_revision: str | None = "20260812_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reminder_proposals",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=True),
        sa.Column("diagnosis_case_id", sa.Uuid(), nullable=True),
        sa.Column("plot_id", sa.Uuid(), nullable=True),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recurrence_days", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('pending', 'accepted', 'declined', 'expired')",
            name="ck_reminder_proposals_status",
        ),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["diagnosis_case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("chat_id", "crop_id", "diagnosis_case_id", "farmer_id", "plot_id"):
        op.create_index(
            op.f(f"ix_reminder_proposals_{column}"), "reminder_proposals", [column]
        )

    op.create_table(
        "reminders",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("proposal_id", sa.Uuid(), nullable=True),
        sa.Column("chat_id", sa.Uuid(), nullable=True),
        sa.Column("diagnosis_case_id", sa.Uuid(), nullable=True),
        sa.Column("plot_id", sa.Uuid(), nullable=True),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recurrence_days", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'done', 'skipped', 'cancelled')",
            name="ck_reminders_status",
        ),
        sa.CheckConstraint(
            "recurrence_days IS NULL OR recurrence_days >= 1",
            name="ck_reminders_recurrence",
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
            ["proposal_id"], ["reminder_proposals.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "chat_id",
        "crop_id",
        "diagnosis_case_id",
        "due_at",
        "farmer_id",
        "plot_id",
        "proposal_id",
        "status",
    ):
        op.create_index(op.f(f"ix_reminders_{column}"), "reminders", [column])


def downgrade() -> None:
    for column in (
        "status",
        "proposal_id",
        "plot_id",
        "farmer_id",
        "due_at",
        "diagnosis_case_id",
        "crop_id",
        "chat_id",
    ):
        op.drop_index(op.f(f"ix_reminders_{column}"), table_name="reminders")
    op.drop_table("reminders")
    for column in ("plot_id", "farmer_id", "diagnosis_case_id", "crop_id", "chat_id"):
        op.drop_index(
            op.f(f"ix_reminder_proposals_{column}"), table_name="reminder_proposals"
        )
    op.drop_table("reminder_proposals")
