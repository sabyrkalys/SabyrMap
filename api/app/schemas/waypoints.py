import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.geometry import GeoJSONPoint


class WaypointCreateRequest(BaseModel):
    name: str
    geom: GeoJSONPoint


class WaypointUpdateRequest(BaseModel):
    name: str | None = None
    geom: GeoJSONPoint | None = None


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    geom: GeoJSONPoint
    created_at: datetime


class WaypointListResponse(BaseModel):
    items: list[WaypointResponse]
    limit: int
    offset: int
