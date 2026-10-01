import uuid
from datetime import datetime, timezone

from geoalchemy2 import Geometry
from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

REGION_STATUSES = ("queued", "running", "ready", "failed", "expired")


class RegionJob(Base):
    """An offline region a user asked for; also the worker's queue row.

    storage_dir is a random folder name under REGIONS_PATH. Several jobs can
    share one folder: a request for a region that is already built reuses it
    instead of cutting it again.
    """

    __tablename__ = "region_jobs"
    __table_args__ = (
        Index("ix_region_jobs_user_created", "user_id", "created_at"),
        Index("ix_region_jobs_status", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    map_id: Mapped[str] = mapped_column(String(64), ForeignKey("map_catalog.id"), nullable=False)
    name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    bbox: Mapped[str] = mapped_column(Geometry(geometry_type="POLYGON", srid=4326, spatial_index=False), nullable=False)
    max_zoom: Mapped[int] = mapped_column(Integer, nullable=False)
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="queued")
    progress: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    storage_dir: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    files: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )
    ready_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
