"""add admin reset otp fields

Revision ID: d3e4f5a6b7c8
Revises: c1fc8532700a
Create Date: 2026-07-13 12:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd3e4f5a6b7c8'
down_revision: Union[str, Sequence[str], None] = 'c1fc8532700a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('admin_users', sa.Column('reset_otp_code', sa.String(), nullable=True))
    op.add_column('admin_users', sa.Column('reset_otp_expires_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('admin_users', 'reset_otp_expires_at')
    op.drop_column('admin_users', 'reset_otp_code')
