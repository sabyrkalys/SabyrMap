import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class RegionRequest(BaseModel):
    map_id: str
    # [west, south, east, north], degrees.
    bbox: list[float] = Field(min_length=4, max_length=4)
    max_zoom: int
    name: str | None = Field(default=None, max_length=255)


class EstimateRequest(BaseModel):
    map_id: str
    bbox: list[float] = Field(min_length=4, max_length=4)
    max_zoom: int


class TilesetEstimateResponse(BaseModel):
    tileset: str
    tiles: int
    bytes: int


class EstimateResponse(BaseModel):
    parts: list[TilesetEstimateResponse]
    style_bytes: int
    total_bytes: int
    max_bytes: int
    allowed: bool


class RegionFile(BaseModel):
    name: str
    size: int
    sha256: str


class RegionResponse(BaseModel):
    id: uuid.UUID
    map_id: str
    name: str | None
    bbox: list[float]
    max_zoom: int
    version: str
    status: str
    progress: float
    size_bytes: int | None
    files: list[RegionFile]
    error: str | None
    created_at: datetime
    ready_at: datetime | None
    expires_at: datetime | None


class RegionListResponse(BaseModel):
    items: list[RegionResponse]
