"""add listener badge tags

Revision ID: lstag0001
Revises: rf1nd0001
Create Date: 2026-08-12 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = 'lstag0001'
down_revision = 'rf1nd0001'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'listener_badge_tags',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(), nullable=False, unique=True),
        sa.Column('color', sa.String(), nullable=False, server_default='#E11D48'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.add_column(
        'listeners',
        sa.Column('badge_tag_id', sa.Integer(), sa.ForeignKey('listener_badge_tags.id'), nullable=True),
    )


def downgrade():
    op.drop_column('listeners', 'badge_tag_id')
    op.drop_table('listener_badge_tags')
