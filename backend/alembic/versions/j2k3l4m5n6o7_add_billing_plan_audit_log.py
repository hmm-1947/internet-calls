"""add billing plan audit log

Revision ID: j2k3l4m5n6o7
Revises: e3aabe2d7f5a
Create Date: 2026-07-15 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'j2k3l4m5n6o7'
down_revision: Union[str, Sequence[str], None] = 'e3aabe2d7f5a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'billing_plan_audit_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('action', sa.String(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=True),
        sa.Column('plan_name', sa.String(), nullable=False),
        sa.Column('admin_id', sa.Integer(), nullable=True),
        sa.Column('admin_username', sa.String(), nullable=True),
        sa.Column('details', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['admin_id'], ['admin_users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_billing_plan_audit_logs_action'), 'billing_plan_audit_logs', ['action'], unique=False)
    op.create_index(op.f('ix_billing_plan_audit_logs_id'), 'billing_plan_audit_logs', ['id'], unique=False)
    op.create_index(op.f('ix_billing_plan_audit_logs_plan_id'), 'billing_plan_audit_logs', ['plan_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_billing_plan_audit_logs_plan_id'), table_name='billing_plan_audit_logs')
    op.drop_index(op.f('ix_billing_plan_audit_logs_id'), table_name='billing_plan_audit_logs')
    op.drop_index(op.f('ix_billing_plan_audit_logs_action'), table_name='billing_plan_audit_logs')
    op.drop_table('billing_plan_audit_logs')
