"""add track measurement fields

Revision ID: 7d7472006ec0
Revises: 45208d1707c8
Create Date: 2026-09-13 10:49:04.200049

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7d7472006ec0'
down_revision: Union[str, None] = '45208d1707c8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("tracks", sa.Column("started_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("tracks", sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True))
    op.execute(
        "ALTER TABLE tracks ALTER COLUMN geom TYPE geometry(LINESTRINGZ, 4326) USING ST_Force3D(geom)"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE tracks ALTER COLUMN geom TYPE geometry(LINESTRING, 4326) USING ST_Force2D(geom)"
    )
    op.drop_column("tracks", "finished_at")
    op.drop_column("tracks", "started_at")
