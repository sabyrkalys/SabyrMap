"""create map_catalog and region_jobs tables

Revision ID: 8e4c2a9d1f07
Revises: 6b60b2668648
Create Date: 2026-10-01 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import geoalchemy2
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '8e4c2a9d1f07'
down_revision: Union[str, None] = '6b60b2668648'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "map_catalog",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("provider_id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("format", sa.String(length=16), nullable=False),
        sa.Column("style_path", sa.String(length=255), nullable=False),
        sa.Column("min_zoom", sa.Integer(), nullable=False),
        sa.Column("max_zoom", sa.Integer(), nullable=False),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("downloadable", sa.Boolean(), nullable=False),
        sa.Column("can_be_overlay", sa.Boolean(), nullable=False),
        sa.Column("attribution", sa.String(length=512), nullable=True),
        sa.Column("sort", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "region_jobs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("map_id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=True),
        sa.Column(
            "bbox", geoalchemy2.Geometry(geometry_type="POLYGON", srid=4326, spatial_index=False), nullable=False
        ),
        sa.Column("max_zoom", sa.Integer(), nullable=False),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("progress", sa.Float(), nullable=False),
        sa.Column("storage_dir", sa.String(length=64), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("files", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ready_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["map_id"], ["map_catalog.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_region_jobs_user_created", "region_jobs", ["user_id", "created_at"])
    op.create_index("ix_region_jobs_status", "region_jobs", ["status"])


def downgrade() -> None:
    op.drop_index("ix_region_jobs_status", table_name="region_jobs")
    op.drop_index("ix_region_jobs_user_created", table_name="region_jobs")
    op.drop_table("region_jobs")
    op.drop_table("map_catalog")
