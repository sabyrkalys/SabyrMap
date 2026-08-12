"""create tracks table

Revision ID: f0a2386014e2
Revises: baa61ba1c472
Create Date: 2026-08-13 01:57:13.517823

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import geoalchemy2

# revision identifiers, used by Alembic.
revision: str = 'f0a2386014e2'
down_revision: Union[str, None] = 'baa61ba1c472'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "tracks",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column(
            "geom", geoalchemy2.Geometry(geometry_type="LINESTRING", srid=4326, spatial_index=False), nullable=False
        ),
        sa.ForeignKeyConstraint(["id"], ["resources.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_tracks_geom", "tracks", ["geom"], postgresql_using="gist")


def downgrade() -> None:
    op.drop_index("idx_tracks_geom", table_name="tracks")
    op.drop_table("tracks")
