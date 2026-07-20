"""add gift audit log

Revision ID: p9q0r1s2t3u4
Revises: cbba7b6ce524
Create Date: 2026-07-20 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'p9q0r1s2t3u4'
down_revision: Union[str, Sequence[str], None] = 'cbba7b6ce524'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'gift_audit_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('action', sa.String(), nullable=False),
        sa.Column('gift_id', sa.Integer(), nullable=True),
        sa.Column('gift_name', sa.String(), nullable=False),
        sa.Column('admin_id', sa.Integer(), nullable=True),
        sa.Column('admin_username', sa.String(), nullable=True),
        sa.Column('details', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['admin_id'], ['admin_users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_gift_audit_logs_action'), 'gift_audit_logs', ['action'], unique=False)
    op.create_index(op.f('ix_gift_audit_logs_id'), 'gift_audit_logs', ['id'], unique=False)
    op.create_index(op.f('ix_gift_audit_logs_gift_id'), 'gift_audit_logs', ['gift_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_gift_audit_logs_gift_id'), table_name='gift_audit_logs')
    op.drop_index(op.f('ix_gift_audit_logs_id'), table_name='gift_audit_logs')
    op.drop_index(op.f('ix_gift_audit_logs_action'), table_name='gift_audit_logs')
    op.drop_table('gift_audit_logs')
