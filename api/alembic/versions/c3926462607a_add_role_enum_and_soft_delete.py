"""add role enum and soft delete

Revision ID: c3926462607a
Revises: c1486bd260ac
Create Date: 2026-08-12 12:04:11.953589

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'c3926462607a'
down_revision: Union[str, None] = 'c1486bd260ac'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

role_enum = postgresql.ENUM('owner', 'admin', 'member', 'viewer', name='role')


def upgrade() -> None:
    role_enum.create(op.get_bind(), checkfirst=True)

    op.add_column('organizations', sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))

    op.drop_constraint('users_email_key', 'users', type_='unique')
    op.create_index(
        'uq_users_email_active', 'users', ['email'], unique=True,
        postgresql_where=sa.text('deleted_at IS NULL'),
    )

    op.alter_column(
        'users', 'role',
        existing_type=sa.String(length=20),
        type_=role_enum,
        postgresql_using='role::role',
        nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        'users', 'role',
        existing_type=role_enum,
        type_=sa.String(length=20),
        nullable=False,
    )
    op.drop_index('uq_users_email_active', table_name='users')
    op.create_unique_constraint('users_email_key', 'users', ['email'])
    op.drop_column('users', 'deleted_at')
    op.drop_column('organizations', 'deleted_at')

    role_enum.drop(op.get_bind(), checkfirst=True)
