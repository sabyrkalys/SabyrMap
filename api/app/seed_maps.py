"""Fills the map catalog for a published map version (run after a build).

    python -m app.seed_maps --version v1 --region "Украина"

Upserts the server's maps; their attribution is read from the PMTiles
metadata of the archives each map uses, so a new source brings its own credits.
"""

import argparse
import html
import re

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models.map_catalog import MapCatalogEntry
from app.services import maps, pmtiles

# id, name template, style_path, format, min/max zoom, can_be_overlay
_MAPS = [
    ("server-hybrid-day", "{region} · спутник + дороги", "style/hybrid-day", "vector", 0, 20, False),
    ("server-hybrid-night", "{region} · ночь", "style/hybrid-night", "vector", 0, 20, False),
    ("server-vector-day", "{region} · только дороги", "style/vector-day", "vector", 0, 20, False),
    ("server-vector-night", "{region} · только дороги (ночь)", "style/vector-night", "vector", 0, 20, False),
    ("server-satellite", "{region} · спутник", "satellite/{z}/{x}/{y}", "raster", 0, 16, True),
]


def _strip_html(text: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", text))).strip()


def _attribution(entry: MapCatalogEntry) -> str | None:
    parts = []
    for tileset in maps.tilesets_for(entry):
        path = maps.tileset_path(entry.version, tileset)
        if not path.exists():
            continue
        text = _strip_html(str(pmtiles.read_metadata(path).get("attribution", "")))
        if text and text not in parts:
            parts.append(text)
    return " · ".join(parts) or None


def seed(db: Session, *, version: str, region: str) -> list[MapCatalogEntry]:
    entries = []
    for sort, (map_id, name, style_path, fmt, min_zoom, max_zoom, overlay) in enumerate(_MAPS):
        entry = db.get(MapCatalogEntry, map_id) or MapCatalogEntry(id=map_id)
        entry.provider_id = "server"
        entry.name = name.format(region=region)
        entry.style_path = style_path
        entry.format = fmt
        entry.min_zoom = min_zoom
        entry.max_zoom = max_zoom
        entry.version = version
        entry.downloadable = True
        entry.can_be_overlay = overlay
        entry.sort = sort
        entry.attribution = _attribution(entry)
        db.add(entry)
        entries.append(entry)
    db.flush()
    return entries


def main() -> None:
    parser = argparse.ArgumentParser(description="Fill the map catalog for a map version.")
    parser.add_argument("--version", required=True, help="folder under TILES_PATH, e.g. v1")
    parser.add_argument("--region", required=True, help='shown in map names, e.g. "Казахстан"')
    args = parser.parse_args()
    db = SessionLocal()
    try:
        for entry in seed(db, version=args.version, region=args.region):
            print(f"{entry.id}: {entry.name} [{entry.attribution}]")
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    main()
