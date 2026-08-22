"""add type and note to waypoints

Revision ID: 45208d1707c8
Revises: 74dacc626025
Create Date: 2026-08-22 08:07:51.796435

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '45208d1707c8'
down_revision: Union[str, None] = '74dacc626025'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "waypoints",
        sa.Column("type", sa.String(length=50), nullable=False, server_default="generic"),
    )
    op.add_column(
        "waypoints",
        sa.Column("note", sa.String(length=500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("waypoints", "note")
    op.drop_column("waypoints", "type")
