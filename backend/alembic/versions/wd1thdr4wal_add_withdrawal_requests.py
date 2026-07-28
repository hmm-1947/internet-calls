"""add withdrawal_requests table

Revision ID: wd1thdr4wal
Revises: PLACEHOLDER_SET_TO_YOUR_CURRENT_HEAD
Create Date: 2026-07-28
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'wd1thdr4wal'
down_revision = 'z4a5b6c7d8e9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'withdrawal_requests',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('listener_id', sa.Integer(), sa.ForeignKey('listeners.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('coins', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(), nullable=False, server_default='pending', index=True),
        sa.Column('admin_id', sa.Integer(), sa.ForeignKey('admin_users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('admin_username', sa.String(), nullable=True),
        sa.Column('decided_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), index=True),
    )
    op.create_index('ix_withdrawal_requests_listener_created', 'withdrawal_requests', ['listener_id', 'created_at'])


def downgrade() -> None:
    op.drop_index('ix_withdrawal_requests_listener_created', table_name='withdrawal_requests')
    op.drop_table('withdrawal_requests')
