"""Create database-backed one-hour weather snapshots.

Revision ID: 20260812_0006
Revises: 20260812_0005
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0006"
down_revision: str | None = "20260812_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "weather_snapshots",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("plot_id", sa.Uuid(), nullable=True),
        sa.Column("weather_type", sa.String(length=24), nullable=False),
        sa.Column("location_key", sa.String(length=64), nullable=False),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("provider", sa.String(length=50), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "weather_type IN ('current_phone', 'current_plot', 'plot_forecast')",
            name="ck_weather_snapshots_type",
        ),
        sa.CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_weather_latitude"),
        sa.CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_weather_longitude"),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer_profiles.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["plot_id"], ["plots.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "farmer_id",
            "weather_type",
            "location_key",
            name="uq_weather_snapshot_cache_key",
        ),
    )
    for column in ("farmer_id", "fetched_at", "plot_id", "weather_type"):
        op.create_index(
            op.f(f"ix_weather_snapshots_{column}"), "weather_snapshots", [column]
        )


def downgrade() -> None:
    for column in ("weather_type", "plot_id", "fetched_at", "farmer_id"):
        op.drop_index(
            op.f(f"ix_weather_snapshots_{column}"), table_name="weather_snapshots"
        )
    op.drop_table("weather_snapshots")
