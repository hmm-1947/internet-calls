"""add call fields to chat messages

Revision ID: callchat1a2b3c
Revises: 0469a8f49644
Create Date: 2026-08-07 06:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'callchat1a2b3c'
down_revision: Union[str, Sequence[str], None] = '0469a8f49644'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('chat_messages', sa.Column('call_type', sa.String(), nullable=True))
    op.add_column('chat_messages', sa.Column('call_status', sa.String(), nullable=True))
    op.add_column('chat_messages', sa.Column('call_duration_seconds', sa.Integer(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('chat_messages', 'call_duration_seconds')
    op.drop_column('chat_messages', 'call_status')
    op.drop_column('chat_messages', 'call_type')
