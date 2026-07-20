"""add gift fields to chat messages

Revision ID: q5r6s7t8u9v0
Revises: p9q0r1s2t3u4
Create Date: 2026-07-20 00:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'q5r6s7t8u9v0'
down_revision: Union[str, Sequence[str], None] = 'p9q0r1s2t3u4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('chat_messages', sa.Column('gift_id', sa.Integer(), nullable=True))
    op.add_column('chat_messages', sa.Column('gift_name', sa.String(), nullable=True))
    op.add_column('chat_messages', sa.Column('gift_icon', sa.String(), nullable=True))
    op.add_column('chat_messages', sa.Column('gift_coins', sa.Integer(), nullable=True))
    op.add_column('chat_messages', sa.Column('call_id', sa.Integer(), nullable=True))
    op.create_index(op.f('ix_chat_messages_gift_id'), 'chat_messages', ['gift_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_chat_messages_gift_id'), table_name='chat_messages')
    op.drop_column('chat_messages', 'call_id')
    op.drop_column('chat_messages', 'gift_coins')
    op.drop_column('chat_messages', 'gift_icon')
    op.drop_column('chat_messages', 'gift_name')
    op.drop_column('chat_messages', 'gift_id')
