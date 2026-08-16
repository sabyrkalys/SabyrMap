import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.geometry import GeoJSONPoint


class WaypointCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    geom: GeoJSONPoint


class WaypointUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
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
