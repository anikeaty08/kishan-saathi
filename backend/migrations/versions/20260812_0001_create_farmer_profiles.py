"""Create farmer profiles.

Revision ID: 20260812_0001
Revises: None
Create Date: 2026-08-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "farmer_profiles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("cognito_sub", sa.String(length=128), nullable=False),
        sa.Column("cognito_username", sa.String(length=128), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("email_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("name", sa.String(length=100), nullable=True),
        sa.Column("preferred_language", sa.String(length=16), nullable=True),
        sa.Column("area_unit", sa.String(length=16), server_default="acre", nullable=False),
        sa.Column("notifications_enabled", sa.Boolean(), server_default="false", nullable=False),
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
            "area_unit IN ('acre', 'hectare')",
            name="ck_farmer_profiles_area_unit",
        ),
        sa.CheckConstraint(
            "preferred_language IS NULL OR length(preferred_language) BETWEEN 2 AND 16",
            name="ck_farmer_profiles_language_length",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_farmer_profiles_cognito_sub"),
        "farmer_profiles",
        ["cognito_sub"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_farmer_profiles_cognito_sub"), table_name="farmer_profiles")
    op.drop_table("farmer_profiles")
