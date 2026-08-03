"""add profile edit fields to users

The edit profile screen lets a user change their username and their registered
email / phone number. Each of those has a 24h cool-down, tracked by the
`*_changed_at` columns, and the new email/phone is held in the
`pending_contact_*` columns until its OTP is verified so an abandoned change
never replaces a working login identifier.

Revision ID: prf1ledit01
Revises: sgnupfl0w01
Create Date: 2026-08-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'prf1ledit01'
down_revision: Union[str, Sequence[str], None] = 'sgnupfl0w01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('username_changed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('email_changed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('phone_changed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('pending_contact_channel', sa.String(), nullable=True))
    op.add_column('users', sa.Column('pending_contact_identifier', sa.String(), nullable=True))
    op.add_column('users', sa.Column('pending_contact_otp_code', sa.String(), nullable=True))
    op.add_column('users', sa.Column('pending_contact_otp_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        'users',
        sa.Column('pending_contact_otp_attempts', sa.Integer(), server_default='0', nullable=False),
    )


def downgrade() -> None:
    op.drop_column('users', 'pending_contact_otp_attempts')
    op.drop_column('users', 'pending_contact_otp_expires_at')
    op.drop_column('users', 'pending_contact_otp_code')
    op.drop_column('users', 'pending_contact_identifier')
    op.drop_column('users', 'pending_contact_channel')
    op.drop_column('users', 'phone_changed_at')
    op.drop_column('users', 'email_changed_at')
    op.drop_column('users', 'username_changed_at')
