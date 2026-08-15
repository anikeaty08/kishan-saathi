"""Create chat-send idempotency and crop-cycle history.

Revision ID: 20260812_0011
Revises: 20260812_0010
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260812_0011"
down_revision: str | None = "20260812_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "crop_cycle_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("crop_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(length=16), nullable=False),
        sa.Column("event_date", sa.Date(), nullable=False),
        sa.Column(
            "occurred_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("event_type IN ('started', 'closed')", name="ck_crop_cycle_events_type"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("farmer_id", "crop_id", "event_type", "occurred_at"):
        op.create_index(f"ix_crop_cycle_events_{column}", "crop_cycle_events", [column])
    op.execute(
        """
        INSERT INTO crop_cycle_events
            (id, farmer_id, crop_id, event_type, event_date, occurred_at)
        SELECT gen_random_uuid(), farmer_id, id, 'started', cycle_started_on, created_at
        FROM crops
        """
    )
    op.execute(
        """
        INSERT INTO crop_cycle_events
            (id, farmer_id, crop_id, event_type, event_date, occurred_at)
        SELECT gen_random_uuid(), farmer_id, id, 'closed', cycle_ended_on, updated_at
        FROM crops WHERE cycle_ended_on IS NOT NULL
        """
    )
    op.create_table(
        "chat_send_operations",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("chat_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("response", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "farmer_id",
            "chat_id",
            "idempotency_key",
            name="uq_chat_send_operations_key",
        ),
    )
    op.create_index("ix_chat_send_operations_farmer_id", "chat_send_operations", ["farmer_id"])
    op.create_index("ix_chat_send_operations_chat_id", "chat_send_operations", ["chat_id"])


def downgrade() -> None:
    op.drop_table("chat_send_operations")
    op.drop_table("crop_cycle_events")
