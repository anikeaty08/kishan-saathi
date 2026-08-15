"""Create cross-replica provider rate-limit buckets.

Revision ID: 20260815_0018
Revises: 20260815_0017
Create Date: 2026-08-15
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260815_0018"
down_revision: str | None = "20260815_0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "auth_rate_limit_buckets",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("subject_key", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("window_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("request_count", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "subject_key", "window_start", name="uq_auth_rate_limit_bucket"
        ),
    )
    op.create_index(
        op.f("ix_auth_rate_limit_buckets_subject_key"),
        "auth_rate_limit_buckets",
        ["subject_key"],
    )
    op.create_index(
        op.f("ix_auth_rate_limit_buckets_window_start"),
        "auth_rate_limit_buckets",
        ["window_start"],
    )
    op.create_table(
        "provider_rate_limit_buckets",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation", sa.String(length=40), nullable=False),
        sa.Column("window_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("request_count", sa.Integer(), nullable=False),
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
        sa.UniqueConstraint(
            "farmer_id",
            "operation",
            "window_start",
            name="uq_provider_rate_limit_bucket",
        ),
    )
    op.create_index(
        op.f("ix_provider_rate_limit_buckets_farmer_id"),
        "provider_rate_limit_buckets",
        ["farmer_id"],
    )
    op.create_index(
        op.f("ix_provider_rate_limit_buckets_operation"),
        "provider_rate_limit_buckets",
        ["operation"],
    )
    op.create_index(
        op.f("ix_provider_rate_limit_buckets_window_start"),
        "provider_rate_limit_buckets",
        ["window_start"],
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_provider_rate_limit_buckets_window_start"),
        table_name="provider_rate_limit_buckets",
    )
    op.drop_index(
        op.f("ix_provider_rate_limit_buckets_operation"),
        table_name="provider_rate_limit_buckets",
    )
    op.drop_index(
        op.f("ix_provider_rate_limit_buckets_farmer_id"),
        table_name="provider_rate_limit_buckets",
    )
    op.drop_table("provider_rate_limit_buckets")
    op.drop_index(
        op.f("ix_auth_rate_limit_buckets_window_start"),
        table_name="auth_rate_limit_buckets",
    )
    op.drop_index(
        op.f("ix_auth_rate_limit_buckets_subject_key"),
        table_name="auth_rate_limit_buckets",
    )
    op.drop_table("auth_rate_limit_buckets")
