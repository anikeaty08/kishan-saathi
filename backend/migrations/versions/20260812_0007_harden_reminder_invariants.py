"""Harden reminder proposal and acceptance invariants.

Revision ID: 20260812_0007
Revises: 20260812_0006
Create Date: 2026-08-12
"""

from collections.abc import Sequence

from alembic import op

revision: str = "20260812_0007"
down_revision: str | None = "20260812_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_check_constraint(
        "ck_reminder_proposals_recurrence",
        "reminder_proposals",
        "recurrence_days IS NULL OR recurrence_days >= 1",
    )
    op.create_unique_constraint(
        "uq_reminders_proposal_id", "reminders", ["proposal_id"]
    )


def downgrade() -> None:
    op.drop_constraint("uq_reminders_proposal_id", "reminders", type_="unique")
    op.drop_constraint(
        "ck_reminder_proposals_recurrence",
        "reminder_proposals",
        type_="check",
    )
