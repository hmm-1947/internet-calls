"""add profile photo url

Revision ID: k3l4m5n6o7p8
Revises: j2k3l4m5n6o7
Create Date: 2026-07-16
"""
from alembic import op
import sqlalchemy as sa

revision = 'k3l4m5n6o7p8'
down_revision = 'j2k3l4m5n6o7'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('users', sa.Column('photo_url', sa.String(), nullable=True))
    op.add_column('listeners', sa.Column('photo_url', sa.String(), nullable=True))

def downgrade():
    op.drop_column('users', 'photo_url')
    op.drop_column('listeners', 'photo_url')