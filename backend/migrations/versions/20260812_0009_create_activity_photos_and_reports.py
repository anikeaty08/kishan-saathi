"""Create activity photos and approved diagnosis reports.

Revision ID: 20260812_0009
Revises: 20260812_0008
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260812_0009"
down_revision: str | None = "20260812_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "object_deletion_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("reason", sa.String(length=64), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_error_type", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("last_attempted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "next_attempt_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "owner_id", "object_key", name="uq_object_deletion_jobs_object"
        ),
    )
    op.create_index("ix_object_deletion_jobs_owner_id", "object_deletion_jobs", ["owner_id"])
    op.create_index(
        "ix_object_deletion_jobs_next_attempt_at",
        "object_deletion_jobs",
        ["next_attempt_at"],
    )

    op.create_table(
        "activity_photos",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("activity_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False),
        sa.Column("height", sa.Integer(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "width >= 32 AND height >= 32", name="ck_activity_photos_dimensions"
        ),
        sa.ForeignKeyConstraint(["activity_id"], ["activities.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key", name="uq_activity_photos_object_key"),
    )
    op.create_index("ix_activity_photos_farmer_id", "activity_photos", ["farmer_id"])
    op.create_index("ix_activity_photos_activity_id", "activity_photos", ["activity_id"])

    op.create_table(
        "diagnosis_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("diagnosis_case_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("snapshot", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("approved_fields", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('active', 'revoked')", name="ck_diagnosis_reports_status"
        ),
        sa.ForeignKeyConstraint(
            ["diagnosis_case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("farmer_id", "diagnosis_case_id", "token_hash", "status", "expires_at"):
        op.create_index(
            f"ix_diagnosis_reports_{column}",
            "diagnosis_reports",
            [column],
            unique=column == "token_hash",
        )

    op.create_table(
        "diagnosis_report_images",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("farmer_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("report_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_image_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["report_id"], ["diagnosis_reports.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["source_image_id"], ["diagnosis_images.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key"),
    )
    for column in ("farmer_id", "report_id"):
        op.create_index(
            f"ix_diagnosis_report_images_{column}",
            "diagnosis_report_images",
            [column],
        )


def downgrade() -> None:
    op.drop_table("diagnosis_report_images")
    op.drop_table("diagnosis_reports")
    op.drop_table("activity_photos")
    op.drop_table("object_deletion_jobs")
