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

# id, name template, style_path, format, min/max zoom, can_be_overlay (every
# map can also lie over another one; a hybrid goes with its satellite)
_MAPS = [
    ("server-hybrid-day-nobuildings", "Гибрид", "style/hybrid-day-nobuildings", "vector", 0, 20, True),
    ("server-satellite", "{region} · спутник", "satellite/{z}/{x}/{y}", "raster", 0, 17, True),
]
# «server-hybrid-day», «server-vector-day», «server-hybrid-night» и
# «server-vector-night» убраны из списка по просьбе пользователя
# (2026-10-17); seed() ниже удаляет их и на уже засеянных базах.

# Maps that are only layers over another map, under their own provider (shown
# in the app as «Яндекс»): Yandex roads z0–17 with OSM street names.
_LAYERS = [
    ("server-roads", "Яндекс дороги (слой)", "style/roads", "vector", 0, 17, True),
]
LAYERS_PROVIDER = "server-layers"

# Our own imagery (a satellite pass over one area, transparent outside it),
# shown in the app under «Снимки»; a map or a layer over another map.
_IMAGERY = [
    ("server-zolotoj-kolodez", "Золотой Колодезь · снимок 19.09.2026", "zolotoj-kolodez/{z}/{x}/{y}", "raster", 8, 18,
     True),
]
IMAGERY_PROVIDER = "server-imagery"


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
    maps = ([("server", m) for m in _MAPS] + [(LAYERS_PROVIDER, m) for m in _LAYERS]
            + [(IMAGERY_PROVIDER, m) for m in _IMAGERY])
    for sort, (provider, (map_id, name, style_path, fmt, min_zoom, max_zoom, overlay)) in enumerate(maps):
        entry = db.get(MapCatalogEntry, map_id) or MapCatalogEntry(id=map_id)
        entry.provider_id = provider
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

    # Entries this script used to manage but no longer lists (e.g. a map
    # dropped from _MAPS/_LAYERS/_IMAGERY) — delete rather than leave stale.
    managed_providers = {"server", LAYERS_PROVIDER, IMAGERY_PROVIDER}
    kept_ids = {e.id for e in entries}
    for stale in db.query(MapCatalogEntry).filter(MapCatalogEntry.provider_id.in_(managed_providers)):
        if stale.id not in kept_ids:
            db.delete(stale)

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
