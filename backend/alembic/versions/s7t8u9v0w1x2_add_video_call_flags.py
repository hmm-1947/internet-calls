"""add video call toggle flags to users

Revision ID: s7t8u9v0w1x2
Revises: r6s7t8u9v0w1
Create Date: 2026-07-21 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 's7t8u9v0w1x2'
down_revision: Union[str, Sequence[str], None] = 'r6s7t8u9v0w1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('video_call_enabled', sa.Boolean(), nullable=False, server_default='1'))
    op.add_column('users', sa.Column('video_call_disabled_by_admin', sa.Boolean(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('users', 'video_call_disabled_by_admin')
    op.drop_column('users', 'video_call_enabled')
