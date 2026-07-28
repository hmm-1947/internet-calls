"""add session expiry

Revision ID: z4a5b6c7d8e9
Revises: y3z4a5b6c7d8
Create Date: 2026-07-28 00:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'z4a5b6c7d8e9'
down_revision: Union[str, Sequence[str], None] = 'y3z4a5b6c7d8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('sessions', sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True))
    op.execute("UPDATE sessions SET expires_at = created_at + INTERVAL '30 days' WHERE expires_at IS NULL")
    op.alter_column('sessions', 'expires_at', nullable=False)


def downgrade() -> None:
    op.drop_column('sessions', 'expires_at')
