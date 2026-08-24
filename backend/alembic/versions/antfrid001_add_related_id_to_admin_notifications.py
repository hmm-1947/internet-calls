"""add related_id to admin_notifications

Revision ID: antfrid001
Revises: lvcflag001
Create Date: 2026-08-24 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'antfrid001'
down_revision: Union[str, Sequence[str], None] = 'lvcflag001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('admin_notifications', sa.Column('related_id', sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column('admin_notifications', 'related_id')
