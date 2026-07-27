"""empty message

Revision ID: 11e6dce4efee
Revises: u2v3w4x5y6z7
Create Date: 2026-07-27 12:20:13.573514

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '11e6dce4efee'
down_revision: Union[str, Sequence[str], None] = 'u2v3w4x5y6z7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = {col['name'] for col in inspector.get_columns('listeners')}
    if 'age' not in existing_columns:
        op.add_column('listeners', sa.Column('age', sa.Integer(), nullable=True))
    if 'occupation' not in existing_columns:
        op.add_column('listeners', sa.Column('occupation', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = {col['name'] for col in inspector.get_columns('listeners')}
    if 'occupation' in existing_columns:
        op.drop_column('listeners', 'occupation')
    if 'age' in existing_columns:
        op.drop_column('listeners', 'age')
