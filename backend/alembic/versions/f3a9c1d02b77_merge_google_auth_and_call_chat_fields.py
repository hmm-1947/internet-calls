"""merge google auth and call chat fields migrations

Revision ID: f3a9c1d02b77
Revises: g0og1eauth01, callchat1a2b3c
Create Date: 2026-08-08 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f3a9c1d02b77'
down_revision: Union[str, Sequence[str], None] = ('g0og1eauth01', 'callchat1a2b3c')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
