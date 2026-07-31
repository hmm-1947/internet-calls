"""add phone to admin_users

Revision ID: ap1prof1le01
Revises: wc2gm1n5nap5
Create Date: 2026-07-31
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ap1prof1le01'
down_revision: Union[str, Sequence[str], None] = 'wc2gm1n5nap5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('admin_users', sa.Column('phone', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('admin_users', 'phone')
