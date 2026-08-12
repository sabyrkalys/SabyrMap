"""create waypoints table

Revision ID: baa61ba1c472
Revises: c07edf723a81
Create Date: 2026-08-13 01:11:05.371317

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import geoalchemy2


# revision identifiers, used by Alembic.
revision: str = 'baa61ba1c472'
down_revision: Union[str, None] = 'c07edf723a81'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "waypoints",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("geom", geoalchemy2.Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False),
        sa.ForeignKeyConstraint(["id"], ["resources.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_waypoints_geom", "waypoints", ["geom"], postgresql_using="gist")


def downgrade() -> None:
    op.drop_index("idx_waypoints_geom", table_name="waypoints")
    op.drop_table("waypoints")
