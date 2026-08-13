import uuid

from sqlalchemy.orm import Session

from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.track import Track
from app.models.waypoint import Waypoint


def create_waypoint(db: Session, *, org_id: uuid.UUID, owner_id: uuid.UUID, name: str, geom) -> Waypoint:
    resource = Resource(org_id=org_id, owner_id=owner_id, resource_type=ResourceType.WAYPOINT)
    db.add(resource)
    db.flush()
    waypoint = Waypoint(id=resource.id, name=name, geom=geom)
    db.add(waypoint)
    db.flush()
    return waypoint


def create_track(db: Session, *, org_id: uuid.UUID, owner_id: uuid.UUID, name: str, geom) -> Track:
    resource = Resource(org_id=org_id, owner_id=owner_id, resource_type=ResourceType.TRACK)
    db.add(resource)
    db.flush()
    track = Track(id=resource.id, name=name, geom=geom)
    db.add(track)
    db.flush()
    return track
