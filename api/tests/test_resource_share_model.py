import pytest
from sqlalchemy.exc import IntegrityError

from app.models.enums import Permission, ResourceType, ShareScope
from app.models.organization import Organization
from app.models.resource import Resource
from app.models.resource_share import ResourceShare
from app.models.user import User


def _org_owner_resource(db_session, email="owner5@acme.test"):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()
    owner = User(org_id=org.id, email=email, password_hash="hashed")
    db_session.add(owner)
    db_session.flush()
    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    return org, owner, resource


def test_user_scope_share_requires_target_user(db_session):
    org, owner, resource = _org_owner_resource(db_session)
    other = User(org_id=org.id, email="other@acme.test", password_hash="hashed")
    db_session.add(other)
    db_session.flush()

    share = ResourceShare(
        resource_id=resource.id,
        shared_with_user_id=other.id,
        scope=ShareScope.USER,
        permission=Permission.VIEW,
        created_by=owner.id,
    )
    db_session.add(share)
    db_session.flush()

    assert share.id is not None


def test_organization_scope_share_forbids_target_user(db_session):
    org, owner, resource = _org_owner_resource(db_session, email="owner6@acme.test")

    share = ResourceShare(
        resource_id=resource.id,
        shared_with_user_id=owner.id,
        scope=ShareScope.ORGANIZATION,
        permission=Permission.VIEW,
        created_by=owner.id,
    )
    db_session.add(share)
    with pytest.raises(IntegrityError):
        db_session.flush()


def test_user_scope_share_forbids_null_target(db_session):
    org, owner, resource = _org_owner_resource(db_session, email="owner7@acme.test")

    share = ResourceShare(
        resource_id=resource.id,
        shared_with_user_id=None,
        scope=ShareScope.USER,
        permission=Permission.VIEW,
        created_by=owner.id,
    )
    db_session.add(share)
    with pytest.raises(IntegrityError):
        db_session.flush()


def test_duplicate_share_to_same_user_rejected(db_session):
    org, owner, resource = _org_owner_resource(db_session, email="owner8@acme.test")
    other = User(org_id=org.id, email="other2@acme.test", password_hash="hashed")
    db_session.add(other)
    db_session.flush()

    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=other.id,
        scope=ShareScope.USER, permission=Permission.VIEW, created_by=owner.id,
    ))
    db_session.flush()

    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=other.id,
        scope=ShareScope.USER, permission=Permission.EDIT, created_by=owner.id,
    ))
    with pytest.raises(IntegrityError):
        db_session.flush()


def test_duplicate_organization_scope_share_rejected(db_session):
    org, owner, resource = _org_owner_resource(db_session, email="owner9@acme.test")

    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=None,
        scope=ShareScope.ORGANIZATION, permission=Permission.VIEW, created_by=owner.id,
    ))
    db_session.flush()

    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=None,
        scope=ShareScope.ORGANIZATION, permission=Permission.EDIT, created_by=owner.id,
    ))
    with pytest.raises(IntegrityError):
        db_session.flush()
