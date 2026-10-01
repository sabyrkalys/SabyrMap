from sqlalchemy import Boolean, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class MapCatalogEntry(Base):
    """One map on our tile server, as listed by GET /maps.

    style_path is relative to the public tiles URL: a Martin style
    ("style/hybrid-day") for vector maps, or a tile template
    ("satellite/{z}/{x}/{y}") for raster ones.
    """

    __tablename__ = "map_catalog"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    provider_id: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    format: Mapped[str] = mapped_column(String(16), nullable=False)  # raster | vector
    style_path: Mapped[str] = mapped_column(String(255), nullable=False)
    min_zoom: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_zoom: Mapped[int] = mapped_column(Integer, nullable=False, default=22)
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    downloadable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    can_be_overlay: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    attribution: Mapped[str | None] = mapped_column(String(512), nullable=True)
    sort: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
