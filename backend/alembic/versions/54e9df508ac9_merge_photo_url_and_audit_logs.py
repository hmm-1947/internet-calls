"""merge photo_url and audit_logs

Revision ID: 54e9df508ac9
Revises: 118e780f7636, 4011f36f3d72
Create Date: 2026-07-16 14:43:24.952644

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '54e9df508ac9'
down_revision: Union[str, Sequence[str], None] = ('118e780f7636', '4011f36f3d72')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
