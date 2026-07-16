"""merge gift and billing migrations

Revision ID: a6935c8dd47f
Revises: h2i3j4k5l6m7, j2k3l4m5n6o7
Create Date: 2026-07-16 09:54:20.981195

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a6935c8dd47f'
down_revision: Union[str, Sequence[str], None] = ('h2i3j4k5l6m7', 'j2k3l4m5n6o7')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
