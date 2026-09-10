"""add signup offer settings table

Revision ID: sgnupoffr01
Revises: lst0nl1ne1
Create Date: 2026-09-10 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'sgnupoffr01'
down_revision: Union[str, Sequence[str], None] = 'lst0nl1ne1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'signup_offer_settings',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('from_date', sa.Date(), nullable=True),
        sa.Column('to_date', sa.Date(), nullable=True),
        sa.Column('coin_amount', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table('signup_offer_settings')
