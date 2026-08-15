"""Create scoped chat sessions and messages.

Revision ID: 20260812_0004
Revises: 20260812_0003
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0004"
down_revision: str | None = "20260812_0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "chat_sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("scope_type", sa.String(length=16), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=True),
        sa.Column("plot_id", sa.Uuid(), nullable=True),
        sa.Column("diagnosis_case_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(length=150), nullable=False),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
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
            "scope_type IN ('general', 'farm', 'plot', 'scan')",
            name="ck_chat_sessions_scope_type",
        ),
        sa.CheckConstraint(
            "(scope_type = 'general' AND farm_id IS NULL AND plot_id IS NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'farm' AND farm_id IS NOT NULL AND plot_id IS NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'plot' AND plot_id IS NOT NULL "
            "AND diagnosis_case_id IS NULL) OR "
            "(scope_type = 'scan' AND diagnosis_case_id IS NOT NULL)",
            name="ck_chat_sessions_scope_shape",
        ),
        sa.ForeignKeyConstraint(
            ["diagnosis_case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("diagnosis_case_id", "farm_id", "farmer_id", "plot_id", "scope_type"):
        op.create_index(op.f(f"ix_chat_sessions_{column}"), "chat_sessions", [column])

    op.create_table(
        "chat_messages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("chat_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("model", sa.String(length=100), nullable=True),
        sa.Column("provider_response_id", sa.String(length=255), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("role IN ('user', 'assistant')", name="ck_chat_messages_role"),
        sa.CheckConstraint("sequence >= 1", name="ck_chat_messages_sequence_positive"),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("chat_id", "sequence", name="uq_chat_messages_sequence"),
    )
    op.create_index(op.f("ix_chat_messages_chat_id"), "chat_messages", ["chat_id"])
    op.create_index(op.f("ix_chat_messages_farmer_id"), "chat_messages", ["farmer_id"])


def downgrade() -> None:
    op.drop_index(op.f("ix_chat_messages_farmer_id"), table_name="chat_messages")
    op.drop_index(op.f("ix_chat_messages_chat_id"), table_name="chat_messages")
    op.drop_table("chat_messages")
    for column in ("scope_type", "plot_id", "farmer_id", "farm_id", "diagnosis_case_id"):
        op.drop_index(op.f(f"ix_chat_sessions_{column}"), table_name="chat_sessions")
    op.drop_table("chat_sessions")
