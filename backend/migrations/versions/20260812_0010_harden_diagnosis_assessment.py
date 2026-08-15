"""Enforce one active assessment per diagnosis case.

Revision ID: 20260812_0010
Revises: 20260812_0009
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0010"
down_revision: str | None = "20260812_0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            WITH ranked AS (
                SELECT id,
                       row_number() OVER (
                           PARTITION BY case_id
                           ORDER BY confidence DESC, created_at DESC, id DESC
                       ) AS position
                FROM diagnosis_assessments
                WHERE is_active
            )
            UPDATE diagnosis_assessments AS assessment
            SET is_active = false
            FROM ranked
            WHERE assessment.id = ranked.id AND ranked.position > 1
            """
        )
    )
    op.create_index(
        "uq_diagnosis_assessments_active_case",
        "diagnosis_assessments",
        ["case_id"],
        unique=True,
        postgresql_where="is_active",
    )


def downgrade() -> None:
    op.drop_index(
        "uq_diagnosis_assessments_active_case",
        table_name="diagnosis_assessments",
    )
