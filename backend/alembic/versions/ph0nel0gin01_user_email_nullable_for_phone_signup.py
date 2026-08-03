"""make users.email nullable for phone-only signups

Revision ID: ph0nel0gin01
Revises: ap1prof1le01
Create Date: 2026-07-31 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'ph0nel0gin01'
down_revision: Union[str, Sequence[str], None] = 'ap1prof1le01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column('users', 'email', existing_type=sa.String(), nullable=True)


def downgrade() -> None:
    op.alter_column('users', 'email', existing_type=sa.String(), nullable=False)
