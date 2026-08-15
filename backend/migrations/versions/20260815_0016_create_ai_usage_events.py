"""Create privacy-preserving append-only AI usage events.

Revision ID: 20260815_0016
Revises: 20260815_0015
Create Date: 2026-08-15
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260815_0016"
down_revision: str | None = "20260815_0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ai_usage_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation", sa.String(length=40), nullable=False),
        sa.Column("model", sa.String(length=100), nullable=False),
        sa.Column("provider_response_id", sa.String(length=255), nullable=True),
        sa.Column("request_count", sa.Integer(), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=False),
        sa.Column("cached_input_tokens", sa.Integer(), nullable=False),
        sa.Column("cache_write_tokens", sa.Integer(), nullable=False),
        sa.Column("output_tokens", sa.Integer(), nullable=False),
        sa.Column("reasoning_tokens", sa.Integer(), nullable=False),
        sa.Column("total_tokens", sa.Integer(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_ai_usage_events_farmer_id"), "ai_usage_events", ["farmer_id"])
    op.create_index(op.f("ix_ai_usage_events_operation"), "ai_usage_events", ["operation"])
    op.create_index(op.f("ix_ai_usage_events_model"), "ai_usage_events", ["model"])
    op.create_index(
        "ix_ai_usage_farmer_created",
        "ai_usage_events",
        ["farmer_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_ai_usage_farmer_created", table_name="ai_usage_events")
    op.drop_index(op.f("ix_ai_usage_events_model"), table_name="ai_usage_events")
    op.drop_index(op.f("ix_ai_usage_events_operation"), table_name="ai_usage_events")
    op.drop_index(op.f("ix_ai_usage_events_farmer_id"), table_name="ai_usage_events")
    op.drop_table("ai_usage_events")
