"""add gifts

Revision ID: g1h2i3j4k5l6
Revises: d3e4f5a6b7c8, 14cac8b68f50, f5a6b7c8d9e0
Create Date: 2026-07-15 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'g1h2i3j4k5l6'
down_revision: Union[str, Sequence[str], None] = ('d3e4f5a6b7c8', '14cac8b68f50', 'f5a6b7c8d9e0')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'gifts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('coins', sa.Integer(), nullable=False),
        sa.Column('icon', sa.String(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_gifts_id'), 'gifts', ['id'], unique=False)

    op.create_table(
        'gift_transactions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('listener_id', sa.Integer(), nullable=False),
        sa.Column('gift_id', sa.Integer(), nullable=False),
        sa.Column('coins', sa.Integer(), nullable=False),
        sa.Column('call_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['listener_id'], ['listeners.id']),
        sa.ForeignKeyConstraint(['gift_id'], ['gifts.id']),
        sa.ForeignKeyConstraint(['call_id'], ['calls.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_gift_transactions_id'), 'gift_transactions', ['id'], unique=False)

    op.bulk_insert(
        sa.table(
            'gifts',
            sa.column('name', sa.String),
            sa.column('coins', sa.Integer),
            sa.column('icon', sa.String),
        ),
        [
            {'name': 'Rose', 'coins': 50, 'icon': 'rose'},
            {'name': 'Diamond', 'coins': 500, 'icon': 'diamond'},
            {'name': 'Truffle', 'coins': 120, 'icon': 'truffle'},
        ],
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_gift_transactions_id'), table_name='gift_transactions')
    op.drop_table('gift_transactions')
    op.drop_index(op.f('ix_gifts_id'), table_name='gifts')
    op.drop_table('gifts')
