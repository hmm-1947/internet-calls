"""add call billed_minutes

Revision ID: r6s7t8u9v0w1
Revises: q5r6s7t8u9v0
Create Date: 2026-07-20 00:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'r6s7t8u9v0w1'
down_revision: Union[str, Sequence[str], None] = 'q5r6s7t8u9v0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('calls', sa.Column('billed_minutes', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('calls', 'billed_minutes')
