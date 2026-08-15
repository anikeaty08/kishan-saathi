"""Create multi-image diagnosis cases and model evidence.

Revision ID: 20260812_0003
Revises: 20260812_0002
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0003"
down_revision: str | None = "20260812_0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "diagnosis_cases",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=True),
        sa.Column("plot_id", sa.Uuid(), nullable=True),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("plant_name", sa.String(length=100), nullable=True),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
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
            "status IN ('processing', 'completed', 'failed')",
            name="ck_diagnosis_cases_status",
        ),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("crop_id", "farm_id", "farmer_id", "plot_id"):
        op.create_index(
            op.f(f"ix_diagnosis_cases_{column}"),
            "diagnosis_cases",
            [column],
            unique=False,
        )

    op.create_table(
        "diagnosis_images",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("case_id", sa.Uuid(), nullable=False),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False),
        sa.Column("height", sa.Integer(), nullable=False),
        sa.Column("captured_or_uploaded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("quality_score", sa.Float(), nullable=True),
        sa.Column("quality_flags", sa.JSON(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "width >= 32 AND height >= 32", name="ck_diagnosis_images_dimensions"
        ),
        sa.ForeignKeyConstraint(["case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key", name="uq_diagnosis_images_object_key"),
    )
    op.create_index(op.f("ix_diagnosis_images_case_id"), "diagnosis_images", ["case_id"])
    op.create_index(op.f("ix_diagnosis_images_farmer_id"), "diagnosis_images", ["farmer_id"])

    op.create_table(
        "diagnosis_assessments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("case_id", sa.Uuid(), nullable=False),
        sa.Column("predicted_crop", sa.String(length=100), nullable=False),
        sa.Column("primary_disease", sa.String(length=200), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("confidence_label", sa.String(length=10), nullable=False),
        sa.Column("model_name", sa.String(length=100), nullable=False),
        sa.Column("model_version", sa.String(length=100), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "confidence BETWEEN 0 AND 1", name="ck_assessments_confidence"
        ),
        sa.CheckConstraint(
            "confidence_label IN ('low', 'medium', 'high')",
            name="ck_assessments_confidence_label",
        ),
        sa.ForeignKeyConstraint(["case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_diagnosis_assessments_case_id"), "diagnosis_assessments", ["case_id"]
    )
    op.create_index(
        op.f("ix_diagnosis_assessments_farmer_id"), "diagnosis_assessments", ["farmer_id"]
    )
    op.create_index(
        op.f("ix_diagnosis_assessments_is_active"), "diagnosis_assessments", ["is_active"]
    )

    op.create_table(
        "diagnosis_feedback",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("case_id", sa.Uuid(), nullable=False),
        sa.Column("is_incorrect", sa.Boolean(), nullable=False),
        sa.Column("corrected_crop", sa.String(length=100), nullable=True),
        sa.Column("corrected_disease", sa.String(length=200), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
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
        sa.ForeignKeyConstraint(["case_id"], ["diagnosis_cases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("case_id", name="uq_diagnosis_feedback_case"),
    )
    op.create_index(op.f("ix_diagnosis_feedback_case_id"), "diagnosis_feedback", ["case_id"])
    op.create_index(
        op.f("ix_diagnosis_feedback_farmer_id"), "diagnosis_feedback", ["farmer_id"]
    )

    op.create_table(
        "diagnosis_predictions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("assessment_id", sa.Uuid(), nullable=False),
        sa.Column("image_id", sa.Uuid(), nullable=True),
        sa.Column("scope", sa.String(length=10), nullable=False),
        sa.Column("rank", sa.Integer(), nullable=False),
        sa.Column("crop_name", sa.String(length=100), nullable=False),
        sa.Column("disease_name", sa.String(length=200), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.CheckConstraint("confidence BETWEEN 0 AND 1", name="ck_predictions_confidence"),
        sa.CheckConstraint("rank >= 1", name="ck_predictions_rank"),
        sa.CheckConstraint("scope IN ('combined', 'image')", name="ck_predictions_scope"),
        sa.ForeignKeyConstraint(
            ["assessment_id"], ["diagnosis_assessments.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["image_id"], ["diagnosis_images.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_diagnosis_predictions_assessment_id"),
        "diagnosis_predictions",
        ["assessment_id"],
    )
    op.create_index(
        op.f("ix_diagnosis_predictions_image_id"), "diagnosis_predictions", ["image_id"]
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_diagnosis_predictions_image_id"), table_name="diagnosis_predictions")
    op.drop_index(
        op.f("ix_diagnosis_predictions_assessment_id"), table_name="diagnosis_predictions"
    )
    op.drop_table("diagnosis_predictions")
    op.drop_index(op.f("ix_diagnosis_feedback_farmer_id"), table_name="diagnosis_feedback")
    op.drop_index(op.f("ix_diagnosis_feedback_case_id"), table_name="diagnosis_feedback")
    op.drop_table("diagnosis_feedback")
    op.drop_index(
        op.f("ix_diagnosis_assessments_is_active"), table_name="diagnosis_assessments"
    )
    op.drop_index(
        op.f("ix_diagnosis_assessments_farmer_id"), table_name="diagnosis_assessments"
    )
    op.drop_index(op.f("ix_diagnosis_assessments_case_id"), table_name="diagnosis_assessments")
    op.drop_table("diagnosis_assessments")
    op.drop_index(op.f("ix_diagnosis_images_farmer_id"), table_name="diagnosis_images")
    op.drop_index(op.f("ix_diagnosis_images_case_id"), table_name="diagnosis_images")
    op.drop_table("diagnosis_images")
    for column in ("plot_id", "farmer_id", "farm_id", "crop_id"):
        op.drop_index(op.f(f"ix_diagnosis_cases_{column}"), table_name="diagnosis_cases")
    op.drop_table("diagnosis_cases")
