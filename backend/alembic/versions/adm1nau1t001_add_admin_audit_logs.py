"""add admin audit logs

Revision ID: adm1nau1t001
Revises: lstpres0001
Create Date: 2026-11-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'adm1nau1t001'
down_revision: Union[str, Sequence[str], None] = 'lstpres0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'admin_audit_logs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('admin_id', sa.Integer(), nullable=False),
        sa.Column('admin_username', sa.String(), nullable=False),
        sa.Column('action', sa.String(), nullable=False),
        sa.Column('ip_address', sa.String(), nullable=True),
        sa.Column('latitude', sa.Float(), nullable=True),
        sa.Column('longitude', sa.Float(), nullable=True),
        sa.Column('accuracy_m', sa.Float(), nullable=True),
        sa.Column('location_label', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_admin_audit_logs_id', 'admin_audit_logs', ['id'])
    op.create_index('ix_admin_audit_logs_admin_id', 'admin_audit_logs', ['admin_id'])
    op.create_index('ix_admin_audit_logs_action', 'admin_audit_logs', ['action'])
    op.create_index('ix_admin_audit_logs_created_at', 'admin_audit_logs', ['created_at'])


def downgrade() -> None:
    op.drop_table('admin_audit_logs')
