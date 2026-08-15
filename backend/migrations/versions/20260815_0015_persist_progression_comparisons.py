"""Persist immutable diagnosis progression comparisons.

Revision ID: 20260815_0015
Revises: 20260813_0014
Create Date: 2026-08-15
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260815_0015"
down_revision: str | None = "20260813_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diagnosis_progression_comparisons",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("case_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("earlier_assessment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("later_assessment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("response_language", sa.String(length=8), nullable=False),
        sa.Column("earlier_captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("later_captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("earlier_image_ids", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("later_image_ids", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("trend", sa.String(length=20), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("evidence", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("limitations", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("recommendations", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("image_quality", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("diagnosis_context", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("model_name", sa.String(length=100), nullable=False),
        sa.Column("provider_response_id", sa.String(length=255), nullable=False),
        sa.Column("prompt_version", sa.String(length=32), nullable=False),
        sa.Column("schema_version", sa.String(length=32), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "confidence BETWEEN 0 AND 1",
            name="ck_progression_confidence",
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["earlier_assessment_id"],
            ["diagnosis_assessments.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["later_assessment_id"],
            ["diagnosis_assessments.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "farmer_id",
            "case_id",
            "request_hash",
            name="uq_progression_comparisons_request",
        ),
    )
    op.create_index(
        op.f("ix_diagnosis_progression_comparisons_farmer_id"),
        "diagnosis_progression_comparisons",
        ["farmer_id"],
    )
    op.create_index(
        op.f("ix_diagnosis_progression_comparisons_case_id"),
        "diagnosis_progression_comparisons",
        ["case_id"],
    )
    op.create_index(
        op.f("ix_diagnosis_progression_comparisons_earlier_assessment_id"),
        "diagnosis_progression_comparisons",
        ["earlier_assessment_id"],
    )
    op.create_index(
        op.f("ix_diagnosis_progression_comparisons_later_assessment_id"),
        "diagnosis_progression_comparisons",
        ["later_assessment_id"],
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_diagnosis_progression_comparisons_later_assessment_id"),
        table_name="diagnosis_progression_comparisons",
    )
    op.drop_index(
        op.f("ix_diagnosis_progression_comparisons_earlier_assessment_id"),
        table_name="diagnosis_progression_comparisons",
    )
    op.drop_index(
        op.f("ix_diagnosis_progression_comparisons_case_id"),
        table_name="diagnosis_progression_comparisons",
    )
    op.drop_index(
        op.f("ix_diagnosis_progression_comparisons_farmer_id"),
        table_name="diagnosis_progression_comparisons",
    )
    op.drop_table("diagnosis_progression_comparisons")
