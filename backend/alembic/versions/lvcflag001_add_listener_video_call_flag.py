"""add video call toggle flag to listeners

Revision ID: lvcflag001
Revises: mrgadmtag01
Create Date: 2026-08-18 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'lvcflag001'
down_revision: Union[str, Sequence[str], None] = 'mrgadmtag01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('listeners', sa.Column('video_call_enabled', sa.Boolean(), nullable=False, server_default='1'))


def downgrade() -> None:
    op.drop_column('listeners', 'video_call_enabled')
