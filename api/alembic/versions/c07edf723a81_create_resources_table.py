"""create resources table

Revision ID: c07edf723a81
Revises: c3926462607a
Create Date: 2026-08-12 23:03:31.565103

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c07edf723a81'
down_revision: Union[str, None] = 'c3926462607a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
