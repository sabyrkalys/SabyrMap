from app.database import SessionLocal
from app.services.organizations import create_personal_organization_and_owner

db = SessionLocal()
try:
    user = create_personal_organization_and_owner(
        db, email="test@alpinequest.dev", password_hash="not-a-real-hash"
    )
    db.commit()
    print("created user:", user.id, user.email, user.role, user.org_id)
finally:
    db.close()
