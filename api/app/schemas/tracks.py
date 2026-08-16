import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.geometry import GeoJSONLineString


class TrackCreateRequest(BaseModel):
    name: str
    geom: GeoJSONLineString


class TrackUpdateRequest(BaseModel):
    name: str | None = None
    geom: GeoJSONLineString | None = None


class TrackResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    geom: GeoJSONLineString
    created_at: datetime


class TrackListResponse(BaseModel):
    items: list[TrackResponse]
    limit: int
    offset: int
