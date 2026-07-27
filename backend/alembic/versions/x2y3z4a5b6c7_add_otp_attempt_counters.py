"""add otp attempt counters for brute-force lockout

Revision ID: x2y3z4a5b6c7
Revises: w1x2y3z4a5b6
Create Date: 2026-07-27 00:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'x2y3z4a5b6c7'
down_revision: Union[str, Sequence[str], None] = 'w1x2y3z4a5b6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('reset_otp_attempts', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('admin_users', sa.Column('reset_otp_attempts', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('admin_invites', sa.Column('otp_attempts', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('email_otps', sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('email_otps', 'attempts')
    op.drop_column('admin_invites', 'otp_attempts')
    op.drop_column('admin_users', 'reset_otp_attempts')
    op.drop_column('users', 'reset_otp_attempts')
