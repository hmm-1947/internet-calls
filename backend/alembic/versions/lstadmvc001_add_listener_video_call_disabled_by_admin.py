"""add admin video call disable flag to listeners

Revision ID: lstadmvc001
Revises: sc4le1dx0001
Create Date: 2026-09-19 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'lstadmvc001'
down_revision: Union[str, Sequence[str], None] = 'sc4le1dx0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('listeners', sa.Column('video_call_disabled_by_admin', sa.Boolean(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('listeners', 'video_call_disabled_by_admin')
