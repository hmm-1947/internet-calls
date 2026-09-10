"""default listener is_online status switch to on

Revision ID: lst0nl1ne1
Revises: antfrid001
Create Date: 2026-09-10 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'lst0nl1ne1'
down_revision: Union[str, Sequence[str], None] = 'antfrid001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # The listener status switch now defaults to on for newly created
    # listeners; only an explicit toggle by the listener turns it off.
    op.alter_column(
        'listeners',
        'is_online',
        existing_type=sa.Boolean(),
        nullable=False,
        server_default='1',
    )
    # Existing listeners should also start on, matching the new default.
    op.execute("UPDATE listeners SET is_online = TRUE WHERE is_online IS NOT TRUE")


def downgrade() -> None:
    op.alter_column(
        'listeners',
        'is_online',
        existing_type=sa.Boolean(),
        nullable=True,
        server_default=None,
    )
