"""add listener coins

Revision ID: e4f5a6b7c8d9
Revises: d3e4f5a6b7c8
Create Date: 2026-07-13 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e4f5a6b7c8d9'
down_revision: Union[str, Sequence[str], None] = 'd3e4f5a6b7c8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('listeners', sa.Column('coins', sa.Integer(), nullable=False, server_default='0'))
    op.create_table('listener_coin_transactions',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('listener_id', sa.Integer(), nullable=False),
    sa.Column('amount', sa.Integer(), nullable=False),
    sa.Column('reason', sa.String(), nullable=False),
    sa.Column('call_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['call_id'], ['calls.id'], ),
    sa.ForeignKeyConstraint(['listener_id'], ['listeners.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_listener_coin_transactions_id'), 'listener_coin_transactions', ['id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_listener_coin_transactions_id'), table_name='listener_coin_transactions')
    op.drop_table('listener_coin_transactions')
    op.drop_column('listeners', 'coins')
