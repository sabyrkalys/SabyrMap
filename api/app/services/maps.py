"""The map catalog: which maps our tile server has, as the app expects them,
and which PMTiles archives each map is made of."""

import json
import re
from pathlib import Path

from sqlalchemy.orm import Session

from app.config import settings
from app.models.map_catalog import MapCatalogEntry

PROVIDER_NAMES = {"server": "Сервер карт"}

# A Martin tile template: ".../<source>/{z}/{x}/{y}".
_TILE_TEMPLATE = re.compile(r"/([^/{}]+)/\{z\}/\{x\}/\{y\}$")


def is_style(entry: MapCatalogEntry) -> bool:
    return entry.style_path.startswith("style/")


def style_file(entry: MapCatalogEntry) -> Path:
    """The published style JSON (tools/build/publish_styles.sh) of a vector map."""
    name = entry.style_path.removeprefix("style/")
    return Path(settings.TILES_PATH) / entry.version / "styles" / f"{name}.json"


def tileset_of_template(template: str) -> str | None:
    match = _TILE_TEMPLATE.search(template)
    return match.group(1) if match else None


def load_style(entry: MapCatalogEntry) -> dict:
    return json.loads(style_file(entry).read_text(encoding="utf-8"))


def style_tilesets(style: dict) -> dict[str, str]:
    """Style source id → Martin tileset name, for sources served by Martin."""
    result = {}
    for source_id, source in style.get("sources", {}).items():
        for template in source.get("tiles", []):
            tileset = tileset_of_template(template)
            if tileset:
                result[source_id] = tileset
                break
    return result


def tilesets_for(entry: MapCatalogEntry) -> list[str]:
    """Martin tileset names (= <name>.pmtiles in the version folder) the map
    is drawn from, in a stable order."""
    if is_style(entry):
        names = style_tilesets(load_style(entry)).values()
    else:
        names = [tileset_of_template("/" + entry.style_path)]
    return sorted({n for n in names if n})


def tileset_path(version: str, tileset: str) -> Path:
    return Path(settings.TILES_PATH) / version / f"{tileset}.pmtiles"


def _source_json(entry: MapCatalogEntry) -> dict:
    base = settings.tiles_public_url
    source = {
        "id": entry.id,
        "name": entry.name,
        "format": entry.format,
        # onlineCache = normal tile cache plus offline regions (see the app's
        # StorageMode); maps that can't be downloaded are online only.
        "storageMode": "onlineCache" if entry.downloadable else "onlineOnly",
        "attribution": entry.attribution,
        "minZoom": entry.min_zoom,
        "maxZoom": entry.max_zoom,
        "canBeOverlay": entry.can_be_overlay,
        # Not read by the app yet (phase 4): offline regions and cache busting.
        "downloadable": entry.downloadable,
        "version": entry.version,
    }
    if is_style(entry):
        source["styleUrl"] = f"{base}/{entry.style_path}"
    else:
        source["tileUrlTemplate"] = f"{base}/{entry.style_path}"
    return {k: v for k, v in source.items() if v is not None}


def catalog(db: Session) -> dict:
    """{"providers": [...]} in the shape the app's CatalogRepository.parse reads."""
    entries = db.query(MapCatalogEntry).order_by(MapCatalogEntry.sort, MapCatalogEntry.id).all()
    providers: dict[str, dict] = {}
    for entry in entries:
        provider = providers.setdefault(
            entry.provider_id,
            {
                "id": entry.provider_id,
                "name": PROVIDER_NAMES.get(entry.provider_id, entry.provider_id),
                "isolated": False,
                "sources": [],
            },
        )
        provider["sources"].append(_source_json(entry))
    return {"providers": list(providers.values())}
