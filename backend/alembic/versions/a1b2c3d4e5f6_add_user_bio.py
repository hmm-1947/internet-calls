"""add user bio

Revision ID: a1b2c3d4e5f6
Revises: 14cac8b68f50
Create Date: 2026-07-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '14cac8b68f50'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.add_column('users', sa.Column('bio', sa.String(), nullable=True))


def downgrade():
    op.drop_column('users', 'bio')
