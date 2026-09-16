"""add version-check fields to app_settings

Revision ID: vercheck01
Revises: lstoffdef1
Create Date: 2026-09-15
"""
from alembic import op
import sqlalchemy as sa

revision = 'vercheck01'
down_revision = 'lstoffdef1'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('app_settings', sa.Column('latest_app_version_android', sa.String(), nullable=True))
    op.add_column('app_settings', sa.Column('android_store_url', sa.String(), nullable=True))
    op.add_column('app_settings', sa.Column('latest_app_version_ios', sa.String(), nullable=True))
    op.add_column('app_settings', sa.Column('ios_store_url', sa.String(), nullable=True))
    op.add_column('app_settings', sa.Column('latest_app_version_listener', sa.String(), nullable=True))


def downgrade():
    op.drop_column('app_settings', 'latest_app_version_listener')
    op.drop_column('app_settings', 'ios_store_url')
    op.drop_column('app_settings', 'latest_app_version_ios')
    op.drop_column('app_settings', 'android_store_url')
    op.drop_column('app_settings', 'latest_app_version_android')
