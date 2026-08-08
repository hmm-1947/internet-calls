"""add users.google_uid and make password_hash nullable

Revision ID: g0og1eauth01
Revises: rsvusr1a2b3c
Create Date: 2026-08-07 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'g0og1eauth01'
down_revision: Union[str, Sequence[str], None] = 'rsvusr1a2b3c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('google_uid', sa.String(), nullable=True))
    op.create_index('ix_users_google_uid', 'users', ['google_uid'], unique=True)
    # Accounts created through Google never have a password.
    op.alter_column('users', 'password_hash', existing_type=sa.String(), nullable=True)


def downgrade() -> None:
    op.alter_column('users', 'password_hash', existing_type=sa.String(), nullable=False)
    op.drop_index('ix_users_google_uid', table_name='users')
    op.drop_column('users', 'google_uid')
