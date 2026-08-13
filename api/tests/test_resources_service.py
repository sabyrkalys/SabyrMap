from geoalchemy2.shape import from_shape
from shapely.geometry import LineString, Point

from app.models.organization import Organization
from app.models.resource import Resource
from app.models.user import User
from app.services.resources import create_track, create_waypoint


def test_create_waypoint_creates_resource_and_waypoint_rows(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()
    owner = User(org_id=org.id, email="creator@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    waypoint = create_waypoint(
        db_session, org_id=org.id, owner_id=owner.id, name="Summit",
        geom=from_shape(Point(7.6, 45.9), srid=4326),
    )

    resource = db_session.get(Resource, waypoint.id)
    assert resource is not None
    assert resource.org_id == org.id
    assert resource.owner_id == owner.id
    assert waypoint.name == "Summit"


def test_create_track_creates_resource_and_track_rows(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()
    owner = User(org_id=org.id, email="creator2@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    line = LineString([(7.6, 45.9), (7.7, 46.0)])
    track = create_track(
        db_session, org_id=org.id, owner_id=owner.id, name="Loop",
        geom=from_shape(line, srid=4326),
    )

    resource = db_session.get(Resource, track.id)
    assert resource is not None
    assert resource.org_id == org.id
    assert track.name == "Loop"
