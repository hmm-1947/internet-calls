"""add listener gender and user gender preference

Revision ID: gndr0pref001
Revises: adm2fa000001
"""
from alembic import op
import sqlalchemy as sa

revision = "gndr0pref001"
down_revision = "adm2fa000001"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("listeners", sa.Column("gender", sa.String(), nullable=True))
    op.add_column("users", sa.Column("gender_preference", sa.String(), nullable=True))


def downgrade():
    op.drop_column("users", "gender_preference")
    op.drop_column("listeners", "gender")
