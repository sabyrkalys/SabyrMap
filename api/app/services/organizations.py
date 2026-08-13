from sqlalchemy.orm import Session

from app.models.enums import Role
from app.models.organization import Organization
from app.models.user import User


def create_personal_organization_and_owner(db: Session, *, email: str, password_hash: str) -> User:
    org = Organization(name=email, plan="personal")
    db.add(org)
    db.flush()

    user = User(org_id=org.id, email=email, password_hash=password_hash, role=Role.OWNER)
    db.add(user)
    db.flush()
    return user
