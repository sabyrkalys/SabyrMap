"""create resources table

Revision ID: c07edf723a81
Revises: c3926462607a
Create Date: 2026-08-12 23:03:31.565103

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'c07edf723a81'
down_revision: Union[str, None] = 'c3926462607a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

resource_type_enum = postgresql.ENUM('waypoint', 'track', name='resource_type')


def upgrade() -> None:
    resource_type_enum.create(op.get_bind(), checkfirst=True)

    op.create_table(
        'resources',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('org_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('owner_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('resource_type', postgresql.ENUM('waypoint', 'track', name='resource_type', create_type=False), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['org_id'], ['organizations.id']),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )

    op.create_index('ix_resources_org_id', 'resources', ['org_id'])
    op.create_index('ix_resources_owner_id', 'resources', ['owner_id'])
    op.create_index('ix_resources_org_type', 'resources', ['org_id', 'resource_type'])


def downgrade() -> None:
    op.drop_index('ix_resources_org_type', table_name='resources')
    op.drop_index('ix_resources_owner_id', table_name='resources')
    op.drop_index('ix_resources_org_id', table_name='resources')
    op.drop_table('resources')
    resource_type_enum.drop(op.get_bind(), checkfirst=True)
