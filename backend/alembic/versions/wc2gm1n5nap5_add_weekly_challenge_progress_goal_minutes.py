"""add goal minute snapshot columns to listener_weekly_challenge_progress

Revision ID: wc2gm1n5nap5
Revises: wd1thdr4wal
Create Date: 2026-07-29
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'wc2gm1n5nap5'
down_revision = 'wd1thdr4wal'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('listener_weekly_challenge_progress', sa.Column('goal1_minutes', sa.Integer(), nullable=True))
    op.add_column('listener_weekly_challenge_progress', sa.Column('goal2_minutes', sa.Integer(), nullable=True))
    op.add_column('listener_weekly_challenge_progress', sa.Column('goal3_minutes', sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column('listener_weekly_challenge_progress', 'goal3_minutes')
    op.drop_column('listener_weekly_challenge_progress', 'goal2_minutes')
    op.drop_column('listener_weekly_challenge_progress', 'goal1_minutes')
