from geoalchemy2.shape import from_shape
from shapely.geometry import LineString

from app.models.enums import ResourceType
from app.models.organization import Organization
from app.models.resource import Resource
from app.models.track import Track
from app.models.user import User


def test_create_track_shares_id_with_resource(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner4@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.TRACK)
    db_session.add(resource)
    db_session.flush()

    line = LineString([(7.6, 45.9), (7.7, 46.0)])
    track = Track(id=resource.id, name="Ridge Loop", geom=from_shape(line, srid=4326))
    db_session.add(track)
    db_session.flush()

    assert track.id == resource.id
    assert track.name == "Ridge Loop"
