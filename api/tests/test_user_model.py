import pytest

from app.models.enums import Role
from app.models.organization import Organization
from app.models.user import User


def test_create_user_belongs_to_organization(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    user = User(org_id=org.id, email="owner@acme.test", password_hash="hashed", role=Role.OWNER)
    db_session.add(user)
    db_session.flush()

    assert user.id is not None
    assert user.org_id == org.id
    assert user.role == Role.OWNER


def test_email_is_unique(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup@acme.test", password_hash="a", role=Role.MEMBER))
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup@acme.test", password_hash="b", role=Role.MEMBER))
    from sqlalchemy.exc import IntegrityError

    with pytest.raises(IntegrityError):
        db_session.flush()


def test_role_defaults_to_member(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    user = User(org_id=org.id, email="new@acme.test", password_hash="hashed")
    db_session.add(user)
    db_session.flush()

    assert user.role == Role.MEMBER


def test_role_rejects_invalid_value(db_session):
    from sqlalchemy.exc import DataError

    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    user = User(org_id=org.id, email="bad@acme.test", password_hash="hashed", role="not-a-role")
    db_session.add(user)
    with pytest.raises(DataError):
        db_session.flush()


def test_soft_deleted_user_email_can_be_reused(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    from datetime import datetime, timezone

    old = User(
        org_id=org.id, email="reuse@acme.test", password_hash="a", role=Role.MEMBER,
        deleted_at=datetime.now(timezone.utc),
    )
    db_session.add(old)
    db_session.flush()

    new = User(org_id=org.id, email="reuse@acme.test", password_hash="b", role=Role.MEMBER)
    db_session.add(new)
    db_session.flush()

    assert new.id is not None


def test_active_user_email_still_unique(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup2@acme.test", password_hash="a", role=Role.MEMBER))
    db_session.flush()

    db_session.add(User(org_id=org.id, email="dup2@acme.test", password_hash="b", role=Role.MEMBER))
    from sqlalchemy.exc import IntegrityError

    with pytest.raises(IntegrityError):
        db_session.flush()
