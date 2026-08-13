"""Store structured assistant replies for professional client rendering.

Revision ID: 20260813_0013
Revises: 20260812_0012
Create Date: 2026-08-13
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260813_0013"
down_revision: str | None = "20260812_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("chat_messages", sa.Column("structured_content", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("chat_messages", "structured_content")
