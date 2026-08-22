import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.geometry import GeoJSONPoint


class WaypointCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    type: str = Field(min_length=1)
    note: str | None = Field(default=None, max_length=500)
    geom: GeoJSONPoint


class WaypointUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    type: str | None = Field(default=None, min_length=1)
    note: str | None = Field(default=None, max_length=500)
    geom: GeoJSONPoint | None = None


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    type: str
    note: str | None
    geom: GeoJSONPoint
    can_edit: bool
    created_at: datetime


class WaypointListResponse(BaseModel):
    items: list[WaypointResponse]
    limit: int
    offset: int
