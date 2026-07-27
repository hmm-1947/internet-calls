"""rename user_weekly_challenge_progress to listener_weekly_challenge_progress

Revision ID: t1u2v3w4x5y6
Revises: 116bd823e0c0
Create Date: 2026-07-27 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 't1u2v3w4x5y6'
down_revision: Union[str, Sequence[str], None] = '116bd823e0c0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema.

    The weekly challenge feature was originally (mistakenly) built against
    the user app and tracked user_id. It has been moved to the listener
    app, so the progress table is rebuilt against listeners. Any existing
    rows were tied to the wrong entity (users) and are dropped rather than
    migrated.
    """
    op.drop_index('ix_one_progress_row_per_user_per_week', table_name='user_weekly_challenge_progress')
    op.drop_index(op.f('ix_user_weekly_challenge_progress_week_start'), table_name='user_weekly_challenge_progress')
    op.drop_index(op.f('ix_user_weekly_challenge_progress_user_id'), table_name='user_weekly_challenge_progress')
    op.drop_index(op.f('ix_user_weekly_challenge_progress_id'), table_name='user_weekly_challenge_progress')
    op.drop_table('user_weekly_challenge_progress')

    op.create_table(
        'listener_weekly_challenge_progress',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('listener_id', sa.Integer(), nullable=False),
        sa.Column('week_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('talk_seconds', sa.Integer(), nullable=False),
        sa.Column('goal1_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('goal2_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('goal3_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['listener_id'], ['listeners.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_one_progress_row_per_listener_per_week',
        'listener_weekly_challenge_progress',
        ['listener_id', 'week_start'],
        unique=True,
    )
    op.create_index(op.f('ix_listener_weekly_challenge_progress_id'), 'listener_weekly_challenge_progress', ['id'], unique=False)
    op.create_index(op.f('ix_listener_weekly_challenge_progress_listener_id'), 'listener_weekly_challenge_progress', ['listener_id'], unique=False)
    op.create_index(op.f('ix_listener_weekly_challenge_progress_week_start'), 'listener_weekly_challenge_progress', ['week_start'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_listener_weekly_challenge_progress_week_start'), table_name='listener_weekly_challenge_progress')
    op.drop_index(op.f('ix_listener_weekly_challenge_progress_listener_id'), table_name='listener_weekly_challenge_progress')
    op.drop_index(op.f('ix_listener_weekly_challenge_progress_id'), table_name='listener_weekly_challenge_progress')
    op.drop_index('ix_one_progress_row_per_listener_per_week', table_name='listener_weekly_challenge_progress')
    op.drop_table('listener_weekly_challenge_progress')

    op.create_table(
        'user_weekly_challenge_progress',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('week_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('talk_seconds', sa.Integer(), nullable=False),
        sa.Column('goal1_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('goal2_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('goal3_completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_one_progress_row_per_user_per_week', 'user_weekly_challenge_progress', ['user_id', 'week_start'], unique=True)
    op.create_index(op.f('ix_user_weekly_challenge_progress_id'), 'user_weekly_challenge_progress', ['id'], unique=False)
    op.create_index(op.f('ix_user_weekly_challenge_progress_user_id'), 'user_weekly_challenge_progress', ['user_id'], unique=False)
    op.create_index(op.f('ix_user_weekly_challenge_progress_week_start'), 'user_weekly_challenge_progress', ['week_start'], unique=False)
