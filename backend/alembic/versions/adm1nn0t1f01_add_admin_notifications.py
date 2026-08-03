"""add admin notifications

Feed of events raised by the apps (currently account deletion requests) that
need an admin's attention. Rows are never deleted: "mark as done" flips
`is_done` so the trail of who handled what survives, while `is_read` only
drives the unseen counter in the panel sidebar.

Revision ID: adm1nn0t1f01
Revises: prf1ledit01
Create Date: 2026-08-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'adm1nn0t1f01'
down_revision: Union[str, Sequence[str], None] = 'prf1ledit01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'admin_notifications',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('type', sa.String(), nullable=False),
        sa.Column('title', sa.String(), nullable=False),
        sa.Column('body', sa.Text(), nullable=True),
        sa.Column('subject_type', sa.String(), nullable=True),
        sa.Column('subject_id', sa.Integer(), nullable=True),
        sa.Column('subject_name', sa.String(), nullable=True),
        sa.Column('is_read', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('is_done', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('done_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('done_by_admin_id', sa.Integer(), nullable=True),
        sa.Column('done_by_admin_username', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.ForeignKeyConstraint(['done_by_admin_id'], ['admin_users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_admin_notifications_id'), 'admin_notifications', ['id'], unique=False)
    op.create_index(op.f('ix_admin_notifications_type'), 'admin_notifications', ['type'], unique=False)
    op.create_index(op.f('ix_admin_notifications_subject_id'), 'admin_notifications', ['subject_id'], unique=False)
    op.create_index(op.f('ix_admin_notifications_created_at'), 'admin_notifications', ['created_at'], unique=False)
    op.create_index('ix_admin_notifications_done_created', 'admin_notifications', ['is_done', 'created_at'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_admin_notifications_done_created', table_name='admin_notifications')
    op.drop_index(op.f('ix_admin_notifications_created_at'), table_name='admin_notifications')
    op.drop_index(op.f('ix_admin_notifications_subject_id'), table_name='admin_notifications')
    op.drop_index(op.f('ix_admin_notifications_type'), table_name='admin_notifications')
    op.drop_index(op.f('ix_admin_notifications_id'), table_name='admin_notifications')
    op.drop_table('admin_notifications')
