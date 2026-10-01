"""A tiny map server on disk for map/region tests: header-only PMTiles
archives (enough for estimates) and published styles."""

import json
import struct
from pathlib import Path

import pytest

from app.config import settings
from app.services import pmtiles

TILE_TYPE_IDS = {"mvt": 1, "png": 2, "jpg": 3, "webp": 4}

# Bounds of the fake archives: a patch of the Zailiysky Alatau.
SAT_BOUNDS = (76.0, 42.5, 78.0, 44.0)
OSM_BOUNDS = (75.0, 42.0, 79.0, 44.5)


def pmtiles_header(*, tile_type="webp", min_zoom=0, max_zoom=16, bounds=SAT_BOUNDS,
                   tile_data_length=10_000_000, addressed_tiles=1000) -> bytes:
    data = bytearray(b"PMTiles\x03")
    data += struct.pack(
        "<11Q",
        127, 0,  # root dir
        127, 0,  # metadata
        0, 0,  # leaf dirs
        127, tile_data_length,
        addressed_tiles, addressed_tiles, addressed_tiles,
    )
    data += struct.pack("<6B", 1, 2, 1, TILE_TYPE_IDS[tile_type], min_zoom, max_zoom)
    data += struct.pack("<4i", *(round(v * 1e7) for v in bounds))
    data += struct.pack("<B2i", min_zoom, round((bounds[0] + bounds[2]) / 2 * 1e7),
                        round((bounds[1] + bounds[3]) / 2 * 1e7))
    assert len(data) == 127
    return bytes(data)


def style(name: str, *, hybrid: bool, base="http://tiles.test") -> dict:
    sources = {
        "osm": {"type": "vector", "tiles": [f"{base}/osm/{{z}}/{{x}}/{{y}}"], "maxzoom": 14},
        "overview": {"type": "raster", "tiles": [f"{base}/overview/{{z}}/{{x}}/{{y}}"], "maxzoom": 5},
    }
    layers = [
        {"id": "background", "type": "background"},
        {"id": "overview", "type": "raster", "source": "overview"},
    ]
    if hybrid:
        sources["satellite"] = {"type": "raster", "tiles": [f"{base}/satellite/{{z}}/{{x}}/{{y}}"]}
        layers.append({"id": "satellite", "type": "raster", "source": "satellite"})
    layers += [
        {"id": "roads", "type": "line", "source": "osm", "source-layer": "transportation"},
        {"id": "labels", "type": "symbol", "source": "osm", "source-layer": "place",
         "layout": {"text-field": ["get", "name"], "text-font": ["Noto Sans Regular"]}},
        {"id": "peaks", "type": "symbol", "source": "osm", "source-layer": "mountain_peak",
         "layout": {"text-font": ["Noto Sans Bold"], "icon-image": "peak"}},
    ]
    return {
        "version": 8,
        "name": name,
        "glyphs": f"{base}/font/{{fontstack}}/{{range}}",
        "sprite": f"{base}/sprite/sabyr",
        "sources": sources,
        "layers": layers,
    }


@pytest.fixture()
def map_server(tmp_path, monkeypatch):
    """TILES_PATH with v1 archives and styles; REGIONS_PATH empty."""
    tiles = tmp_path / "tiles"
    v1 = tiles / "v1"
    (v1 / "styles").mkdir(parents=True)
    (v1 / "satellite.pmtiles").write_bytes(pmtiles_header())
    (v1 / "osm.pmtiles").write_bytes(
        pmtiles_header(tile_type="mvt", max_zoom=14, bounds=OSM_BOUNDS, tile_data_length=2_000_000)
    )
    (v1 / "overview.pmtiles").write_bytes(
        pmtiles_header(max_zoom=5, bounds=(-180, -85.0511, 180, 85.0511), tile_data_length=1_000_000,
                       addressed_tiles=1365)
    )
    for kind in ("hybrid", "vector"):
        for theme in ("day", "night"):
            name = f"{kind}-{theme}"
            (v1 / "styles" / f"{name}.json").write_text(json.dumps(style(name, hybrid=kind == "hybrid")))
    regions = tmp_path / "regions"
    regions.mkdir()
    monkeypatch.setattr(settings, "TILES_PATH", str(tiles))
    monkeypatch.setattr(settings, "REGIONS_PATH", str(regions))
    monkeypatch.setattr(settings, "TILES_PUBLIC_URL", "https://maps.test/tiles")
    # The archives above are headers only; pretend `pmtiles extract --dry-run`
    # found one 1000-byte tile per zoom.
    monkeypatch.setattr(pmtiles, "extract_size", lambda path, bbox, max_zoom: (max_zoom + 1, (max_zoom + 1) * 1000))
    return tmp_path


@pytest.fixture()
def seeded(map_server, db_session):
    from app.seed_maps import seed

    seed(db_session, version="v1", region="Алатау")
    return db_session
