"""Offline regions: size estimates, limits, and the request → queue step.
The cutting itself is done by app.worker."""

import secrets
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from geoalchemy2.shape import from_shape, to_shape
from shapely.geometry import box
from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from app.config import settings
from app.models.map_catalog import MapCatalogEntry
from app.models.region_job import RegionJob
from app.services import maps, pmtiles

BBox = tuple[float, float, float, float]  # west, south, east, north

# style.zip: offline style JSON, a few glyph ranges of three fonts, the
# sprite. Measured on the v1 build (≈490 KB).
STYLE_BYTES_ESTIMATE = 500_000
# MBTiles (SQLite pages, index) is a little bigger than the same tiles in
# PMTiles: measured +2…6 %.
MBTILES_OVERHEAD = 1.06

ACTIVE_STATUSES = ("queued", "running", "ready")


class RegionError(Exception):
    """A request the API answers with an error; `status_code` is the HTTP code."""

    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


@dataclass
class TilesetEstimate:
    tileset: str
    tiles: int
    bytes: int


@dataclass
class Estimate:
    parts: list[TilesetEstimate] = field(default_factory=list)
    style_bytes: int = 0

    @property
    def total_bytes(self) -> int:
        return sum(p.bytes for p in self.parts) + self.style_bytes

    @property
    def allowed(self) -> bool:
        return self.total_bytes <= settings.REGION_MAX_BYTES


def normalize_bbox(bbox: list[float]) -> BBox:
    if len(bbox) != 4:
        raise RegionError(422, "bbox: нужно [запад, юг, восток, север]")
    # ~1 m precision: the same area asked twice compares equal.
    west, south, east, north = (round(float(v), 5) for v in bbox)
    if not (-180 <= west < east <= 180 and -85.0511 <= south < north <= 85.0511):
        raise RegionError(422, "bbox: неверные границы")
    return west, south, east, north


def get_downloadable_map(db: Session, map_id: str) -> MapCatalogEntry:
    entry = db.get(MapCatalogEntry, map_id)
    if entry is None:
        raise RegionError(404, "Карта не найдена")
    if not entry.downloadable:
        raise RegionError(422, "Эту карту нельзя скачать")
    return entry


def check_max_zoom(max_zoom: int) -> None:
    if not 0 <= max_zoom <= settings.REGION_MAX_ZOOM:
        raise RegionError(422, f"max_zoom: от 0 до {settings.REGION_MAX_ZOOM}")


def estimate(entry: MapCatalogEntry, bbox: BBox, max_zoom: int) -> Estimate:
    """What the region's files will weigh: the exact tiles of each archive
    in bbox up to max_zoom (capped at the archive's own max zoom: deeper zooms
    are overzoomed on the phone), plus the style."""
    result = Estimate(style_bytes=STYLE_BYTES_ESTIMATE if maps.is_style(entry) else 0)
    for tileset in maps.tilesets_for(entry):
        path = maps.tileset_path(entry.version, tileset)
        if not path.exists():
            raise RegionError(503, f"Нет данных карты: {tileset}")
        header = pmtiles.read_header(path)
        area = pmtiles.intersect_bbox(bbox, header.bounds)
        top = min(max_zoom, header.max_zoom)
        if area is None or top < header.min_zoom:
            continue
        tiles, size = pmtiles.extract_size(path, area, top)
        result.parts.append(TilesetEstimate(tileset, tiles, int(size * MBTILES_OVERHEAD)))
    return result


def bbox_geometry(bbox: BBox):
    return from_shape(box(*bbox), srid=4326)


def job_bbox(job: RegionJob) -> BBox:
    west, south, east, north = to_shape(job.bbox).bounds
    return west, south, east, north


def _envelope(bbox: BBox):
    return func.ST_MakeEnvelope(*bbox, 4326)


def create_job(
    db: Session, *, user_id: uuid.UUID, map_id: str, bbox: list[float], max_zoom: int, name: str | None
) -> tuple[RegionJob, bool]:
    """Queues a region, or returns an equal one that is already built or
    on its way. Returns (job, created)."""
    entry = get_downloadable_map(db, map_id)
    check_max_zoom(max_zoom)
    area = normalize_bbox(bbox)
    now = datetime.now(timezone.utc)

    same_region = (
        db.query(RegionJob)
        .filter(
            RegionJob.map_id == entry.id,
            RegionJob.version == entry.version,
            RegionJob.max_zoom == max_zoom,
            func.ST_Equals(RegionJob.bbox, _envelope(area)),
        )
    )
    mine = (
        same_region.filter(
            RegionJob.user_id == user_id,
            or_(
                RegionJob.status.in_(("queued", "running")),
                and_(RegionJob.status == "ready", RegionJob.expires_at > now),
            ),
        )
        .order_by(RegionJob.created_at.desc())
        .first()
    )
    if mine is not None:
        return mine, False

    recent = db.query(func.count(RegionJob.id)).filter(
        RegionJob.user_id == user_id, RegionJob.created_at > now - timedelta(hours=1)
    ).scalar()
    if recent >= settings.REGION_MAX_PER_HOUR:
        raise RegionError(429, f"Не больше {settings.REGION_MAX_PER_HOUR} регионов в час")

    ready = (
        same_region.filter(RegionJob.status == "ready", RegionJob.expires_at > now)
        .order_by(RegionJob.ready_at.desc())
        .first()
    )
    job = RegionJob(
        user_id=user_id,
        map_id=entry.id,
        name=name,
        bbox=bbox_geometry(area),
        max_zoom=max_zoom,
        version=entry.version,
        created_at=now,
    )
    if ready is not None:
        # Same files, new owner record: nothing is cut again. The folder lives
        # while any ready job points at it (see worker cleanup).
        job.status = "ready"
        job.progress = 1.0
        job.storage_dir = ready.storage_dir
        job.size_bytes = ready.size_bytes
        job.files = ready.files
        job.ready_at = now
        job.expires_at = now + timedelta(hours=settings.REGION_TTL_HOURS)
    else:
        if not estimate(entry, area, max_zoom).allowed:
            raise RegionError(
                413, f"Регион больше {settings.REGION_MAX_BYTES // (1024 * 1024)} МБ: уменьшите область или зум"
            )
        job.status = "queued"
        job.progress = 0.0
        job.storage_dir = secrets.token_hex(16)
    db.add(job)
    db.flush()
    return job, True


def get_own_job(db: Session, user_id: uuid.UUID, job_id: uuid.UUID) -> RegionJob:
    job = db.get(RegionJob, job_id)
    # Someone else's region looks the same as a missing one.
    if job is None or job.user_id != user_id:
        raise RegionError(404, "Регион не найден")
    return job


def file_entry(job: RegionJob, file_name: str) -> dict:
    if job.status != "ready":
        raise RegionError(409, "Регион ещё не готов")
    for f in job.files or []:
        if f["name"] == file_name:
            return f
    raise RegionError(404, "Файл не найден")


def accel_redirect_path(job: RegionJob, file_name: str) -> str:
    return f"/regions-files/{job.storage_dir}/{file_name}"
