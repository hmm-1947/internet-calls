"""add refund fields to user billing purchases

Records refunds reported by Razorpay's `refund.processed` webhook. Coins are
never deducted automatically, so these columns exist purely so the admin panel
and the DB agree with what actually happened to the money.

Revision ID: rf1nd0001
Revises: f3a9c1d02b77
Create Date: 2026-08-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'rf1nd0001'
down_revision: Union[str, Sequence[str], None] = 'f3a9c1d02b77'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('user_billing_purchases', sa.Column('razorpay_refund_id', sa.String(), nullable=True))
    op.add_column(
        'user_billing_purchases',
        sa.Column('refunded_amount_paise', sa.Integer(), server_default='0', nullable=False),
    )
    op.add_column('user_billing_purchases', sa.Column('refunded_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index(
        op.f('ix_user_billing_purchases_razorpay_refund_id'),
        'user_billing_purchases',
        ['razorpay_refund_id'],
        unique=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_user_billing_purchases_razorpay_refund_id'), table_name='user_billing_purchases')
    op.drop_column('user_billing_purchases', 'refunded_at')
    op.drop_column('user_billing_purchases', 'refunded_amount_paise')
    op.drop_column('user_billing_purchases', 'razorpay_refund_id')
