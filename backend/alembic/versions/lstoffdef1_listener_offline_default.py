"""listener is_online default back to off

Revision ID: lstoffdef1
Revises: sgnupoffr01
Create Date: 2026-09-14 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'lstoffdef1'
down_revision: Union[str, Sequence[str], None] = 'sgnupoffr01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column(
        'listeners',
        'is_online',
        existing_type=sa.Boolean(),
        nullable=False,
        server_default='0',
    )
    op.execute(
        "UPDATE listeners SET is_online = FALSE WHERE is_online IS TRUE AND last_seen IS NULL"
    )


def downgrade() -> None:
    op.alter_column(
        'listeners',
        'is_online',
        existing_type=sa.Boolean(),
        nullable=False,
        server_default='1',
    )
