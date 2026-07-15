"""add razorpay fields to purchases

Revision ID: h1i2j3k4l5m6
Revises: g8h9i0j1k2l3
Create Date: 2026-07-15 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'h1i2j3k4l5m6'
down_revision: Union[str, Sequence[str], None] = 'g8h9i0j1k2l3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('user_billing_purchases', sa.Column('razorpay_order_id', sa.String(), nullable=True))
    op.add_column('user_billing_purchases', sa.Column('razorpay_payment_id', sa.String(), nullable=True))
    op.add_column('user_billing_purchases', sa.Column('razorpay_signature', sa.String(), nullable=True))
    op.add_column('user_billing_purchases', sa.Column('failure_reason', sa.String(), nullable=True))
    op.add_column('user_billing_purchases', sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index(op.f('ix_user_billing_purchases_razorpay_order_id'), 'user_billing_purchases', ['razorpay_order_id'], unique=False)
    op.create_index(op.f('ix_user_billing_purchases_razorpay_payment_id'), 'user_billing_purchases', ['razorpay_payment_id'], unique=False)

    # purchases are now created in a "pending" state until Razorpay confirms payment
    op.alter_column('user_billing_purchases', 'status', server_default='pending')


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('user_billing_purchases', 'status', server_default='completed')
    op.drop_index(op.f('ix_user_billing_purchases_razorpay_payment_id'), table_name='user_billing_purchases')
    op.drop_index(op.f('ix_user_billing_purchases_razorpay_order_id'), table_name='user_billing_purchases')
    op.drop_column('user_billing_purchases', 'updated_at')
    op.drop_column('user_billing_purchases', 'failure_reason')
    op.drop_column('user_billing_purchases', 'razorpay_signature')
    op.drop_column('user_billing_purchases', 'razorpay_payment_id')
    op.drop_column('user_billing_purchases', 'razorpay_order_id')
