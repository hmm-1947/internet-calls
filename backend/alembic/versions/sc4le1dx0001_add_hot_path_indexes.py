"""add indexes for hot-path lookups (webhook room lookup, wallets, sessions, chat pairs)

Revision ID: sc4le1dx0001
Revises: vercheck01
Create Date: 2026-09-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'sc4le1dx0001'
down_revision: Union[str, Sequence[str], None] = 'vercheck01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


INDEXES = [
    ('ix_calls_room_name', 'calls', ['room_name']),
    ('ix_call_recordings_call_id', 'call_recordings', ['call_id']),
    ('ix_sessions_user_id', 'sessions', ['user_id']),
    ('ix_sessions_listener_id', 'sessions', ['listener_id']),
    ('ix_sessions_admin_id', 'sessions', ['admin_id']),
    ('ix_coin_transactions_user_id', 'coin_transactions', ['user_id']),
    ('ix_coin_transactions_call_id', 'coin_transactions', ['call_id']),
    ('ix_listener_coin_transactions_listener_id', 'listener_coin_transactions', ['listener_id']),
    ('ix_listener_coin_transactions_call_id', 'listener_coin_transactions', ['call_id']),
    ('ix_gift_transactions_user_id', 'gift_transactions', ['user_id']),
    ('ix_gift_transactions_listener_id', 'gift_transactions', ['listener_id']),
    ('ix_chat_messages_pair_id', 'chat_messages', ['user_id', 'listener_id', 'id']),
    ('ix_chat_settings_owner_other', 'chat_settings', ['owner_type', 'owner_id', 'other_id']),
]


def upgrade() -> None:
    for name, table, columns in INDEXES:
        op.create_index(name, table, columns, if_not_exists=True)


def downgrade() -> None:
    for name, table, _ in reversed(INDEXES):
        op.drop_index(name, table_name=table, if_exists=True)
