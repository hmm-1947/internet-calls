"""add reserved usernames

Revision ID: rsvusr1a2b3c
Revises: z4a5b6c7d8e9
Create Date: 2026-08-07 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'rsvusr1a2b3c'
down_revision: Union[str, Sequence[str], None] = 'z4a5b6c7d8e9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'reserved_usernames',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('username', sa.String(), nullable=False, index=True),
        sa.Column('reserved_by_user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('released_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_index('ix_reserved_usernames_username', table_name='reserved_usernames')
    op.drop_table('reserved_usernames')
