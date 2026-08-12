from app.models.organization import Organization
from app.models.user import User


def test_create_user_belongs_to_organization(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    user = User(org_id=org.id, email="owner@acme.test", password_hash="hashed", role="owner")
    db_session.add(user)
    db_session.flush()

    assert user.id is not None
    assert user.org_id == org.id
    assert user.role == "owner"


def test_email_is_unique(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup@acme.test", password_hash="a", role="member"))
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup@acme.test", password_hash="b", role="member"))
    import pytest
    from sqlalchemy.exc import IntegrityError

    with pytest.raises(IntegrityError):
        db_session.flush()
