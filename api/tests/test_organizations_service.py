from app.models.enums import Role
from app.models.organization import Organization
from app.services.organizations import create_personal_organization_and_owner


def test_creates_personal_org_with_owner(db_session):
    user = create_personal_organization_and_owner(
        db_session, email="solo@example.test", password_hash="hashed",
    )

    org = db_session.get(Organization, user.org_id)
    assert org is not None
    assert org.plan == "personal"
    assert user.role == Role.OWNER
    assert user.email == "solo@example.test"
