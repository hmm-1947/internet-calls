"""add composite indexes on calls(caller_user_id, status) and calls(callee_listener_id, status)

Revision ID: w1x2y3z4a5b6
Revises: fb55fc961b62
Create Date: 2026-07-27 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'w1x2y3z4a5b6'
down_revision: Union[str, Sequence[str], None] = 'fb55fc961b62'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index('ix_calls_caller_status', 'calls', ['caller_user_id', 'status'])
    op.create_index('ix_calls_callee_status', 'calls', ['callee_listener_id', 'status'])


def downgrade() -> None:
    op.drop_index('ix_calls_callee_status', table_name='calls')
    op.drop_index('ix_calls_caller_status', table_name='calls')
