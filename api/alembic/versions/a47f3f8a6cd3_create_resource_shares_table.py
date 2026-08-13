"""create resource_shares table

Revision ID: a47f3f8a6cd3
Revises: f0a2386014e2
Create Date: 2026-08-13 14:38:47.650416

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'a47f3f8a6cd3'
down_revision: Union[str, None] = 'f0a2386014e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create enums - use if not exists via raw SQL to handle both fresh and existing databases
    op.execute("CREATE TYPE share_scope AS ENUM ('user', 'organization')")
    op.execute("CREATE TYPE permission AS ENUM ('view', 'edit')")

    op.create_table(
        "resource_shares",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("resource_id", sa.UUID(), nullable=False),
        sa.Column("shared_with_user_id", sa.UUID(), nullable=True),
        sa.Column("scope", postgresql.ENUM("user", "organization", name="share_scope", create_type=False), nullable=False),
        sa.Column("permission", postgresql.ENUM("view", "edit", name="permission", create_type=False), nullable=False),
        sa.Column("created_by", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["resource_id"], ["resources.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["shared_with_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("resource_id", "shared_with_user_id", name="uq_resource_shares_resource_user"),
        sa.CheckConstraint(
            "(scope = 'user' AND shared_with_user_id IS NOT NULL) OR "
            "(scope = 'organization' AND shared_with_user_id IS NULL)",
            name="ck_resource_shares_scope_consistency",
        ),
    )
    op.create_index("ix_resource_shares_resource_id", "resource_shares", ["resource_id"])
    op.create_index("ix_resource_shares_user_id", "resource_shares", ["shared_with_user_id"])


def downgrade() -> None:
    op.drop_table("resource_shares")
    op.execute("DROP TYPE IF EXISTS permission")
    op.execute("DROP TYPE IF EXISTS share_scope")
