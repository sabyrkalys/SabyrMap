"""add partial unique index for organization-scope resource shares

Revision ID: 74dacc626025
Revises: a47f3f8a6cd3
Create Date: 2026-08-17 00:03:27.490647

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '74dacc626025'
down_revision: Union[str, None] = 'a47f3f8a6cd3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Existing installs may already carry duplicate organization-scope shares
    # on the same resource (Postgres treats NULL as distinct in the
    # (resource_id, shared_with_user_id) unique constraint, so those rows
    # were never rejected). Keep the most recently created row per
    # resource_id and drop the rest before the new index can be created.
    op.execute(
        """
        DELETE FROM resource_shares
        WHERE scope = 'organization'
          AND id NOT IN (
              SELECT DISTINCT ON (resource_id) id
              FROM resource_shares
              WHERE scope = 'organization'
              ORDER BY resource_id, created_at DESC
          )
        """
    )
    op.create_index(
        "uq_resource_shares_resource_org",
        "resource_shares",
        ["resource_id"],
        unique=True,
        postgresql_where=sa.text("scope = 'organization'"),
    )


def downgrade() -> None:
    op.drop_index("uq_resource_shares_resource_org", table_name="resource_shares")
