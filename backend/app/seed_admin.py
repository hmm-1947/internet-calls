import sys
from app.core.database import SessionLocal
from app.models.models import AdminUser
from app.utils.security import hash_password


def create_support_admin(username: str, password: str, email: str | None = None):
    db = SessionLocal()
    try:
        existing = db.query(AdminUser).filter(AdminUser.username == username).first()
        if existing:
            print(f"Admin user '{username}' already exists (id={existing.id})")
            return
        admin = AdminUser(
            username=username,
            email=email,
            password_hash=hash_password(password),
            is_support=True,
            is_active=True,
        )
        db.add(admin)
        db.commit()
        db.refresh(admin)
        print(f"Created support admin '{username}' (id={admin.id})")
    finally:
        db.close()


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python -m app.seed_admin <username> <password> [email]")
        sys.exit(1)
    username = sys.argv[1]
    password = sys.argv[2]
    email = sys.argv[3] if len(sys.argv) > 3 else None
    create_support_admin(username, password, email)
