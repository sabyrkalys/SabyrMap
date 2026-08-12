import pytest

from app.models.enums import ResourceType
from app.models.organization import Organization
from app.models.resource import Resource
from app.models.user import User


def test_create_resource(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert resource.id is not None
    assert resource.deleted_at is None
    assert resource.resource_type == ResourceType.WAYPOINT


def test_resource_type_rejects_invalid_value(db_session):
    from sqlalchemy.exc import DataError

    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner2@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type="not-a-type")
    db_session.add(resource)
    with pytest.raises(DataError):
        db_session.flush()
