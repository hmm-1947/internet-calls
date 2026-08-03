"""drop email_otps: user sign-up is phone/OTP only

Revision ID: dr0pem41lotp
Revises: usrn4me0001
Create Date: 2026-07-31 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'dr0pem41lotp'
down_revision: Union[str, Sequence[str], None] = 'usrn4me0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # The email-registration endpoints are gone, so the pending-signup table
    # only ever held short-lived OTP rows that nothing reads any more.
    op.drop_table('email_otps')


def downgrade() -> None:
    op.create_table(
        'email_otps',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(), nullable=False),
        sa.Column('otp_code', sa.String(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('phone', sa.String(), nullable=False),
        sa.Column('password_hash', sa.String(), nullable=False),
        sa.Column('is_verified', sa.Boolean(), nullable=True),
        sa.Column('attempts', sa.Integer(), server_default='0', nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_email_otps_id', 'email_otps', ['id'])
    op.create_index('ix_email_otps_email', 'email_otps', ['email'])
