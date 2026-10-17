"""add platform to sessions

Revision ID: webs3ssion01
Revises: lstadmvc001
"""
from alembic import op
import sqlalchemy as sa

revision = "webs3ssion01"
down_revision = "lstadmvc001"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "sessions",
        sa.Column("platform", sa.String(), nullable=True),
    )


def downgrade():
    op.drop_column("sessions", "platform")
