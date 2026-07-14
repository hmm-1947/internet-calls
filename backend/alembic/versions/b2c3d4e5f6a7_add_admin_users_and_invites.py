"""add admin users and invites

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-07-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, Sequence[str], None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.create_table(
        'admin_users',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('username', sa.String(), nullable=False),
        sa.Column('email', sa.String(), nullable=True),
        sa.Column('password_hash', sa.String(), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.true()),
        sa.Column('is_support', sa.Boolean(), server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_admin_users_username', 'admin_users', ['username'], unique=True)
    op.create_index('ix_admin_users_email', 'admin_users', ['email'], unique=True)

    op.create_table(
        'admin_invites',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('token', sa.String(), nullable=False),
        sa.Column('email', sa.String(), nullable=True),
        sa.Column('otp_code', sa.String(), nullable=True),
        sa.Column('otp_expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('email_verified', sa.Boolean(), server_default=sa.false()),
        sa.Column('is_used', sa.Boolean(), server_default=sa.false()),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_admin_invites_token', 'admin_invites', ['token'], unique=True)

    op.add_column('sessions', sa.Column('admin_id', sa.Integer(), sa.ForeignKey('admin_users.id'), nullable=True))


def downgrade():
    op.drop_column('sessions', 'admin_id')
    op.drop_index('ix_admin_invites_token', table_name='admin_invites')
    op.drop_table('admin_invites')
    op.drop_index('ix_admin_users_email', table_name='admin_users')
    op.drop_index('ix_admin_users_username', table_name='admin_users')
    op.drop_table('admin_users')
