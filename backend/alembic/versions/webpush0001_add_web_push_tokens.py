"""add web push tokens

Revision ID: webpush0001
Revises: webs3ssion01
"""
from alembic import op
import sqlalchemy as sa

revision = "webpush0001"
down_revision = "webs3ssion01"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "web_push_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_web_push_tokens_id", "web_push_tokens", ["id"])
    op.create_index("ix_web_push_tokens_user_id", "web_push_tokens", ["user_id"])
    op.create_index("ix_web_push_tokens_token", "web_push_tokens", ["token"], unique=True)


def downgrade():
    op.drop_index("ix_web_push_tokens_token", table_name="web_push_tokens")
    op.drop_index("ix_web_push_tokens_user_id", table_name="web_push_tokens")
    op.drop_index("ix_web_push_tokens_id", table_name="web_push_tokens")
    op.drop_table("web_push_tokens")
