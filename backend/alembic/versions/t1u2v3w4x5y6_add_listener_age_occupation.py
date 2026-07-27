"""add age and occupation to listeners

Revision ID: t1u2v3w4x5y6
Revises: s7t8u9v0w1x2
Create Date: 2026-07-27 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 't1u2v3w4x5y6'
down_revision: Union[str, Sequence[str], None] = 's7t8u9v0w1x2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('listeners', sa.Column('age', sa.Integer(), nullable=True))
    op.add_column('listeners', sa.Column('occupation', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('listeners', 'occupation')
    op.drop_column('listeners', 'age')
