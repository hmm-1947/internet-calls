"""add is_active and activated_at to weekly_challenge_settings

Revision ID: u2v3w4x5y6z7
Revises: t1u2v3w4x5y6
Create Date: 2026-07-27 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'u2v3w4x5y6z7'
down_revision: Union[str, Sequence[str], None] = 't1u2v3w4x5y6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'weekly_challenge_settings',
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('false')),
    )
    op.add_column(
        'weekly_challenge_settings',
        sa.Column('activated_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('weekly_challenge_settings', 'activated_at')
    op.drop_column('weekly_challenge_settings', 'is_active')
