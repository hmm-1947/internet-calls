"""add photo url to admin users

Revision ID: admphot001
Revises: rf1nd0001
Create Date: 2026-08-12

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'admphot001'
down_revision = 'rf1nd0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('admin_users', sa.Column('photo_url', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('admin_users', 'photo_url')
