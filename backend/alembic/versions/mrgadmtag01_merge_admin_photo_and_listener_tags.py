"""merge admin photo and listener tags heads

Revision ID: mrgadmtag01
Revises: admphot001, lstag0001
Create Date: 2026-08-12 00:00:01.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'mrgadmtag01'
down_revision: Union[str, Sequence[str], None] = ('admphot001', 'lstag0001')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
