"""simplify billing plans to coin packs

Revision ID: g8h9i0j1k2l3
Revises: a7b8c9d0e1f2
Create Date: 2026-07-14 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'g8h9i0j1k2l3'
down_revision: Union[str, Sequence[str], None] = 'a7b8c9d0e1f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # billing_plans: drop subscription-style columns, add coin-pack columns
    op.add_column('billing_plans', sa.Column('coins', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('billing_plans', sa.Column('icon', sa.String(), nullable=False, server_default='coin'))
    op.drop_index(op.f('ix_billing_plans_plan_type'), table_name='billing_plans')
    op.drop_column('billing_plans', 'plan_type')
    op.drop_column('billing_plans', 'validity_value')
    op.drop_column('billing_plans', 'description')
    op.drop_column('billing_plans', 'sort_order')
    op.alter_column('billing_plans', 'coins', server_default=None)
    op.alter_column('billing_plans', 'icon', server_default=None)

    # user_billing_purchases: record coins granted instead of a validity window
    op.add_column('user_billing_purchases', sa.Column('coins_purchased', sa.Integer(), nullable=False, server_default='0'))
    op.drop_column('user_billing_purchases', 'starts_at')
    op.drop_column('user_billing_purchases', 'expires_at')
    op.alter_column('user_billing_purchases', 'status', server_default='completed')
    op.alter_column('user_billing_purchases', 'coins_purchased', server_default=None)


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column('user_billing_purchases', sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('user_billing_purchases', sa.Column('starts_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True))
    op.alter_column('user_billing_purchases', 'status', server_default='active')
    op.drop_column('user_billing_purchases', 'coins_purchased')

    op.add_column('billing_plans', sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('billing_plans', sa.Column('description', sa.Text(), nullable=True))
    op.add_column('billing_plans', sa.Column('validity_value', sa.Integer(), nullable=False, server_default='1'))
    op.add_column('billing_plans', sa.Column('plan_type', sa.String(), nullable=False, server_default='monthly'))
    op.create_index(op.f('ix_billing_plans_plan_type'), 'billing_plans', ['plan_type'], unique=False)
    op.drop_column('billing_plans', 'icon')
    op.drop_column('billing_plans', 'coins')
