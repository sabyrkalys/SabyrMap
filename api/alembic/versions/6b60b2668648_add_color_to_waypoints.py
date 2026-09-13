"""add color to waypoints

Revision ID: 6b60b2668648
Revises: 7d7472006ec0
Create Date: 2026-09-13 10:50:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6b60b2668648'
down_revision: Union[str, None] = '7d7472006ec0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "waypoints",
        sa.Column("color", sa.String(length=7), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("waypoints", "color")
