"""add pending_signups and make users.phone nullable

Sign-up now works with either an email or a phone number, so an account may
have only one of the two. The half-finished sign-up (identifier + password,
before the OTP and profile steps) lives in `pending_signups` instead of in
`users`, so an abandoned sign-up never holds on to an email/phone/username.

Revision ID: sgnupfl0w01
Revises: dr0pem41lotp
Create Date: 2026-08-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'sgnupfl0w01'
down_revision: Union[str, Sequence[str], None] = 'dr0pem41lotp'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column('users', 'phone', existing_type=sa.String(), nullable=True)

    op.create_table(
        'pending_signups',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('identifier', sa.String(), nullable=False),
        sa.Column('channel', sa.String(), nullable=False),
        sa.Column('password_hash', sa.String(), nullable=False),
        sa.Column('otp_code', sa.String(), nullable=True),
        sa.Column('otp_expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('otp_attempts', sa.Integer(), server_default='0', nullable=False),
        sa.Column('otp_sent_count', sa.Integer(), server_default='0', nullable=False),
        sa.Column('is_verified', sa.Boolean(), server_default='0', nullable=False),
        sa.Column('signup_token', sa.String(), nullable=True),
        sa.Column('signup_token_expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_pending_signups_id', 'pending_signups', ['id'])
    op.create_index('ix_pending_signups_identifier', 'pending_signups', ['identifier'], unique=True)
    op.create_index('ix_pending_signups_signup_token', 'pending_signups', ['signup_token'], unique=True)


def downgrade() -> None:
    op.drop_index('ix_pending_signups_signup_token', table_name='pending_signups')
    op.drop_index('ix_pending_signups_identifier', table_name='pending_signups')
    op.drop_index('ix_pending_signups_id', table_name='pending_signups')
    op.drop_table('pending_signups')
    op.alter_column('users', 'phone', existing_type=sa.String(), nullable=False)
