"""Remove the obsolete queued chat-turn table.

The revision remains after the historical queue creation migration so existing
Alembic histories stay linear while new deployments converge on direct chat.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "20260819_0019"
down_revision: str | None = "20260815_0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("chat_turns")


def downgrade() -> None:
    raise RuntimeError("The removed chat-turn queue cannot be restored safely")
