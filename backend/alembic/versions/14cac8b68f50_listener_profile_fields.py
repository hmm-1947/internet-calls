"""listener profile fields

Revision ID: 14cac8b68f50
Revises: df466a3713a8
Create Date: 2026-07-12 13:26:15.227567

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '14cac8b68f50'
down_revision: Union[str, Sequence[str], None] = 'df466a3713a8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('listeners', sa.Column('about', sa.String(), nullable=True))
    op.add_column('listeners', sa.Column('tags', sa.String(), nullable=True))
    op.add_column('listeners', sa.Column('languages', sa.String(), nullable=True))

def downgrade() -> None:
    op.drop_column('listeners', 'languages')
    op.drop_column('listeners', 'tags')
    op.drop_column('listeners', 'about')
