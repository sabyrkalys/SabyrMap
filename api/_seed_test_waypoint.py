from geoalchemy2.shape import from_shape
from shapely.geometry import Point

from app.database import SessionLocal
from app.models.user import User
from app.services.resources import create_waypoint

db = SessionLocal()
try:
    user = db.query(User).filter(User.email == "test@alpinequest.dev").one()
    waypoint = create_waypoint(
        db,
        org_id=user.org_id,
        owner_id=user.id,
        name="Trailhead",
        geom=from_shape(Point(7.6, 45.9), srid=4326),
    )
    db.commit()
    print("created waypoint:", waypoint.id, waypoint.name)
finally:
    db.close()
