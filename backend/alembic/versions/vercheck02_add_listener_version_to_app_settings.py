"""add listener app version field to app_settings

Revision ID: vercheck02
Revises: vercheck01
Create Date: 2026-09-11
"""
from alembic import op
import sqlalchemy as sa

revision = 'vercheck02'
down_revision = 'vercheck01'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('app_settings', sa.Column('latest_app_version_listener', sa.String(), nullable=True))


def downgrade():
    op.drop_column('app_settings', 'latest_app_version_listener')
