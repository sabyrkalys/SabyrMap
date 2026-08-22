import uuid

from geoalchemy2 import Geometry
from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Waypoint(Base):
    __tablename__ = "waypoints"

    # spatial_index=False: the GIST index is created explicitly in the migration
    # instead of relying on geoalchemy2's automatic DDL-event index management,
    # so test schema (Base.metadata.create_all) and migration stay predictable.
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("resources.id"), primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    geom: Mapped[str] = mapped_column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    type: Mapped[str] = mapped_column(String(50), nullable=False, server_default="generic")
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
