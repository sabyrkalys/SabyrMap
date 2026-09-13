import re
import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.schemas.geometry import GeoJSONPoint

_HEX_COLOR_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _validate_hex_color(v: str | None) -> str | None:
    if v is not None and not _HEX_COLOR_PATTERN.match(v):
        raise ValueError("color must be a hex string like #RRGGBB")
    return v


class WaypointCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    type: str = Field(min_length=1)
    note: str | None = Field(default=None, max_length=500)
    color: str | None = Field(default=None)
    geom: GeoJSONPoint

    @field_validator("color")
    @classmethod
    def _color_is_hex(cls, v: str | None) -> str | None:
        return _validate_hex_color(v)


class WaypointUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    type: str | None = Field(default=None, min_length=1)
    note: str | None = Field(default=None, max_length=500)
    color: str | None = Field(default=None)
    geom: GeoJSONPoint | None = None

    @field_validator("color")
    @classmethod
    def _color_is_hex(cls, v: str | None) -> str | None:
        return _validate_hex_color(v)


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    type: str
    note: str | None
    color: str | None
    geom: GeoJSONPoint
    can_edit: bool
    created_at: datetime


class WaypointListResponse(BaseModel):
    items: list[WaypointResponse]
    limit: int
    offset: int
