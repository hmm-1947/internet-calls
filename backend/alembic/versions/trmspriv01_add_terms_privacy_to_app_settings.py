"""add terms_of_service and privacy_policy to app_settings

Revision ID: trmspriv01
Revises: adm1nn0t1f01
Create Date: 2026-08-03
"""
from alembic import op
import sqlalchemy as sa

revision = 'trmspriv01'
down_revision = 'adm1nn0t1f01'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('app_settings', sa.Column('terms_of_service', sa.Text(), nullable=True))
    op.add_column('app_settings', sa.Column('privacy_policy', sa.Text(), nullable=True))


def downgrade():
    op.drop_column('app_settings', 'privacy_policy')
    op.drop_column('app_settings', 'terms_of_service')
