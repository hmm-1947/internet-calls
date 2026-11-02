"""listener presence: logged-in flag and admin forced-offline flag

Revision ID: lstpres0001
Revises: webpush0001
Create Date: 2026-11-02 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'lstpres0001'
down_revision: Union[str, Sequence[str], None] = 'webpush0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _columns(table: str) -> set:
    return {c['name'] for c in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    existing = _columns('listeners')
    if 'is_logged_in' not in existing:
        op.add_column('listeners', sa.Column('is_logged_in', sa.Boolean(), nullable=False, server_default=sa.text('false')))
    if 'admin_forced_offline' not in existing:
        op.add_column('listeners', sa.Column('admin_forced_offline', sa.Boolean(), nullable=False, server_default=sa.text('false')))
    op.alter_column('listeners', 'is_online', existing_type=sa.Boolean(), nullable=False, server_default=sa.text('true'))
    op.execute(
        "UPDATE listeners SET is_logged_in = TRUE "
        "WHERE EXISTS (SELECT 1 FROM sessions s WHERE s.listener_id = listeners.id AND s.expires_at > now())"
    )
    op.execute("UPDATE listeners SET is_online = TRUE")


def downgrade() -> None:
    op.alter_column('listeners', 'is_online', existing_type=sa.Boolean(), nullable=False, server_default=sa.text('false'))
    op.drop_column('listeners', 'admin_forced_offline')
    op.drop_column('listeners', 'is_logged_in')
