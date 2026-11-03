"""add admin login otp columns for two-step login

Revision ID: adm2fa000001
Revises: adm1nau1t001
Create Date: 2026-11-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'adm2fa000001'
down_revision: Union[str, Sequence[str], None] = 'adm1nau1t001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('admin_users', sa.Column('login_otp_code', sa.String(), nullable=True))
    op.add_column('admin_users', sa.Column('login_otp_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('admin_users', sa.Column('login_otp_attempts', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('admin_users', 'login_otp_attempts')
    op.drop_column('admin_users', 'login_otp_expires_at')
    op.drop_column('admin_users', 'login_otp_code')
