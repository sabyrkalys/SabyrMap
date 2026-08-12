from geoalchemy2.shape import from_shape
from shapely.geometry import Point

from app.models.enums import ResourceType
from app.models.organization import Organization
from app.models.resource import Resource
from app.models.user import User
from app.models.waypoint import Waypoint


def test_create_waypoint_shares_id_with_resource(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner3@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    waypoint = Waypoint(id=resource.id, name="Trailhead", geom=from_shape(Point(7.6, 45.9), srid=4326))
    db_session.add(waypoint)
    db_session.flush()

    assert waypoint.id == resource.id
    assert waypoint.name == "Trailhead"
