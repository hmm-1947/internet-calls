"""merge heads

Revision ID: 0469a8f49644
Revises: rsvusr1a2b3c, trmspriv01
Create Date: 2026-08-07 11:01:58.992797

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0469a8f49644'
down_revision: Union[str, Sequence[str], None] = ('rsvusr1a2b3c', 'trmspriv01')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
