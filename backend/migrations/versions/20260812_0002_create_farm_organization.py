"""Create farms, plots, crops, crop stages, and activities.

Revision ID: 20260812_0002
Revises: 20260812_0001
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0002"
down_revision: str | None = "20260812_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> list[sa.Column[object]]:
    return [
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
    ]


def upgrade() -> None:
    op.create_table(
        "farms",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("farmer_id", "name", name="uq_farms_owner_name"),
    )
    op.create_index(op.f("ix_farms_farmer_id"), "farms", ["farmer_id"], unique=False)

    op.create_table(
        "plots",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("location_label", sa.String(length=255), nullable=True),
        sa.Column("area_value", sa.Numeric(precision=12, scale=3), nullable=True),
        sa.Column("area_unit", sa.String(length=16), nullable=True),
        sa.Column("soil_notes", sa.Text(), nullable=True),
        sa.Column("irrigation_details", sa.Text(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_plots_latitude"),
        sa.CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_plots_longitude"),
        sa.CheckConstraint("area_value IS NULL OR area_value > 0", name="ck_plots_area_positive"),
        sa.CheckConstraint(
            "area_unit IS NULL OR area_unit IN ('acre', 'hectare')",
            name="ck_plots_area_unit",
        ),
        sa.ForeignKeyConstraint(["farm_id"], ["farms.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("farmer_id", "name", name="uq_plots_owner_name"),
    )
    op.create_index(op.f("ix_plots_farm_id"), "plots", ["farm_id"], unique=False)
    op.create_index(op.f("ix_plots_farmer_id"), "plots", ["farmer_id"], unique=False)

    op.create_table(
        "crops",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("plot_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("stage", sa.String(length=100), nullable=False),
        sa.Column("variety", sa.String(length=100), nullable=True),
        sa.Column("sowing_or_transplant_date", sa.Date(), nullable=True),
        sa.Column("cycle_started_on", sa.Date(), nullable=False),
        sa.Column("cycle_ended_on", sa.Date(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint("length(stage) BETWEEN 1 AND 100", name="ck_crops_stage_length"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_crops_farmer_id"), "crops", ["farmer_id"], unique=False)
    op.create_index(op.f("ix_crops_plot_id"), "crops", ["plot_id"], unique=False)

    op.create_table(
        "crop_stage_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("stage", sa.String(length=100), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_crop_stage_events_crop_id"), "crop_stage_events", ["crop_id"], unique=False
    )
    op.create_index(
        op.f("ix_crop_stage_events_farmer_id"),
        "crop_stage_events",
        ["farmer_id"],
        unique=False,
    )

    op.create_table(
        "activities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("plot_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(length=150), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "length(title) BETWEEN 1 AND 150", name="ck_activities_title_length"
        ),
        sa.ForeignKeyConstraint(["crop_id"], ["crops.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["farmer_id"], ["farmer_profiles.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_activities_crop_id"), "activities", ["crop_id"], unique=False)
    op.create_index(
        op.f("ix_activities_farmer_id"), "activities", ["farmer_id"], unique=False
    )
    op.create_index(op.f("ix_activities_plot_id"), "activities", ["plot_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_activities_plot_id"), table_name="activities")
    op.drop_index(op.f("ix_activities_farmer_id"), table_name="activities")
    op.drop_index(op.f("ix_activities_crop_id"), table_name="activities")
    op.drop_table("activities")
    op.drop_index(op.f("ix_crop_stage_events_farmer_id"), table_name="crop_stage_events")
    op.drop_index(op.f("ix_crop_stage_events_crop_id"), table_name="crop_stage_events")
    op.drop_table("crop_stage_events")
    op.drop_index(op.f("ix_crops_plot_id"), table_name="crops")
    op.drop_index(op.f("ix_crops_farmer_id"), table_name="crops")
    op.drop_table("crops")
    op.drop_index(op.f("ix_plots_farmer_id"), table_name="plots")
    op.drop_index(op.f("ix_plots_farm_id"), table_name="plots")
    op.drop_table("plots")
    op.drop_index(op.f("ix_farms_farmer_id"), table_name="farms")
    op.drop_table("farms")
