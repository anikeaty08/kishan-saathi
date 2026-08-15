"""Create durable automatic memory-capture jobs.

Revision ID: 20260812_0012
Revises: 20260812_0011
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260812_0012"
down_revision: str | None = "20260812_0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            WITH ranked AS (
                SELECT prediction.id,
                       row_number() OVER (
                           PARTITION BY prediction.image_id, prediction.rank
                           ORDER BY assessment.created_at, prediction.id
                       ) AS position
                FROM diagnosis_predictions AS prediction
                JOIN diagnosis_assessments AS assessment
                  ON assessment.id = prediction.assessment_id
                WHERE prediction.scope = 'image'
            )
            DELETE FROM diagnosis_predictions AS prediction
            USING ranked
            WHERE prediction.id = ranked.id AND ranked.position > 1
            """
        )
    )
    op.create_index(
        "uq_diagnosis_predictions_image_rank",
        "diagnosis_predictions",
        ["image_id", "rank"],
        unique=True,
        postgresql_where=sa.text("scope = 'image'"),
    )
    op.create_table(
        "memory_capture_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("chat_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_message_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farm_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("plot_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("last_error_type", sa.String(length=100), nullable=True),
        sa.Column(
            "next_attempt_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("lease_token", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("dead_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(farm_id IS NOT NULL AND plot_id IS NULL) OR "
            "(farm_id IS NULL AND plot_id IS NOT NULL)",
            name="ck_memory_capture_jobs_scope",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'processing', 'dead')",
            name="ck_memory_capture_jobs_status",
        ),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["chat_id"], ["chat_sessions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["source_message_id"], ["chat_messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("source_message_id", name="uq_memory_capture_jobs_source_message"),
    )
    for column in (
        "farmer_id",
        "chat_id",
        "source_message_id",
        "farm_id",
        "plot_id",
        "status",
        "next_attempt_at",
        "lease_expires_at",
        "lease_token",
        "dead_at",
    ):
        op.create_index(f"ix_memory_capture_jobs_{column}", "memory_capture_jobs", [column])


def downgrade() -> None:
    op.drop_table("memory_capture_jobs")
    op.drop_index("uq_diagnosis_predictions_image_rank", table_name="diagnosis_predictions")
