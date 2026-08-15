"""Move Mem0 work outside locks using recoverable operation leases.

Revision ID: 20260815_0017
Revises: 20260815_0016
Create Date: 2026-08-15
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260815_0017"
down_revision: str | None = "20260815_0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint(
        "ck_scoped_memory_facts_index_status",
        "scoped_memory_facts",
        type_="check",
    )
    op.create_check_constraint(
        "ck_scoped_memory_facts_index_status",
        "scoped_memory_facts",
        "index_status IN ('pending', 'indexing', 'indexed', 'failed', "
        "'deleting', 'delete_failed')",
    )
    op.add_column(
        "scoped_memory_facts",
        sa.Column("operation_lease_token", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "scoped_memory_facts",
        sa.Column("operation_lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        op.f("ix_scoped_memory_facts_operation_lease_token"),
        "scoped_memory_facts",
        ["operation_lease_token"],
    )
    op.create_index(
        op.f("ix_scoped_memory_facts_operation_lease_expires_at"),
        "scoped_memory_facts",
        ["operation_lease_expires_at"],
    )


def downgrade() -> None:
    op.execute(
        "UPDATE scoped_memory_facts SET index_status = 'failed' "
        "WHERE index_status = 'indexing'"
    )
    op.drop_index(
        op.f("ix_scoped_memory_facts_operation_lease_expires_at"),
        table_name="scoped_memory_facts",
    )
    op.drop_index(
        op.f("ix_scoped_memory_facts_operation_lease_token"),
        table_name="scoped_memory_facts",
    )
    op.drop_column("scoped_memory_facts", "operation_lease_expires_at")
    op.drop_column("scoped_memory_facts", "operation_lease_token")
    op.drop_constraint(
        "ck_scoped_memory_facts_index_status",
        "scoped_memory_facts",
        type_="check",
    )
    op.create_check_constraint(
        "ck_scoped_memory_facts_index_status",
        "scoped_memory_facts",
        "index_status IN ('pending', 'indexed', 'failed', 'deleting', 'delete_failed')",
    )
