import random
import shutil
import sqlite3
import subprocess

import pytest

from app.services import pmtiles
from tests.map_helpers import pmtiles_header

needs_cli = pytest.mark.skipif(shutil.which("pmtiles") is None, reason="pmtiles CLI not installed")


def test_parse_header_reads_zooms_bounds_and_type():
    header = pmtiles.parse_header(
        pmtiles_header(tile_type="mvt", min_zoom=2, max_zoom=14, bounds=(76.5, 42.75, 77.25, 43.5),
                       tile_data_length=5000, addressed_tiles=10)
    )
    assert header.tile_type == "mvt"
    assert (header.min_zoom, header.max_zoom) == (2, 14)
    assert header.bounds == pytest.approx((76.5, 42.75, 77.25, 43.5))


def test_parse_header_rejects_other_files():
    with pytest.raises(pmtiles.PMTilesError):
        pmtiles.parse_header(b"SQLite format 3\x00" + b"\x00" * 120)


def test_tile_id_round_trip_and_known_values():
    assert pmtiles.zxy_to_tileid(0, 0, 0) == 0
    assert pmtiles.zxy_to_tileid(1, 0, 0) == 1
    assert pmtiles.zxy_to_tileid(1, 1, 0) == 4
    rng = random.Random(1)
    for z in range(12):
        for _ in range(20):
            x, y = rng.randrange(1 << z), rng.randrange(1 << z)
            assert pmtiles.tileid_to_zxy(pmtiles.zxy_to_tileid(z, x, y)) == (z, x, y)


def test_extract_size_reads_the_dry_run_report(monkeypatch):
    calls = []

    def fake_run(args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0, "", (
            "2026/10/01 07:31:22 extract.go:450: fetching 21189 tiles, 266 chunks, 66 requests\n"
            "2026/10/01 07:31:22 extract.go:612: Extract transferred 461 MB (overfetch 0.05) "
            "for an archive size of 439 MB\n"
        ))

    monkeypatch.setattr(pmtiles.subprocess, "run", fake_run)

    assert pmtiles.extract_size("/x/satellite.pmtiles", (24.2, 47.95, 24.9, 48.4), 16) == (21189, 439_000_000)
    assert "--dry-run" in calls[0]
    assert "--bbox=24.200000,47.950000,24.900000,48.400000" in calls[0]
    assert "--maxzoom=16" in calls[0]


def test_extract_size_fails_loudly_on_unknown_output(monkeypatch):
    monkeypatch.setattr(pmtiles.subprocess, "run",
                        lambda args, **kw: subprocess.CompletedProcess(args, 0, "", "something else"))
    with pytest.raises(pmtiles.PMTilesError):
        pmtiles.extract_size("/x.pmtiles", (0, 0, 1, 1), 3)


def test_sniff_format_trusts_the_bytes():
    assert pmtiles.sniff_format(b"RIFF\x00\x00\x00\x00WEBPVP8 ") == "webp"
    assert pmtiles.sniff_format(b"\x89PNG\r\n\x1a\n...") == "png"
    assert pmtiles.sniff_format(b"\xff\xd8\xff\xe0") == "jpg"
    assert pmtiles.sniff_format(b"\x1f\x8b\x08") is None


def test_intersect_bbox():
    assert pmtiles.intersect_bbox((0, 0, 10, 10), (5, 5, 20, 20)) == (5, 5, 10, 10)
    assert pmtiles.intersect_bbox((0, 0, 1, 1), (2, 2, 3, 3)) is None


def make_mbtiles(path, zooms=range(0, 4), fmt="png"):
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE metadata (name TEXT, value TEXT);"
        "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);"
    )
    conn.executemany(
        "INSERT INTO metadata VALUES (?, ?)",
        [("name", "test"), ("format", fmt), ("minzoom", str(min(zooms))), ("maxzoom", str(max(zooms))),
         ("bounds", "-180,-85,180,85"), ("attribution", "Test data")],
    )
    tiles = {}
    for z in zooms:
        for x in range(1 << z):
            for y in range(1 << z):
                data = f"{z}/{x}/{y}".encode()
                tiles[(z, x, y)] = data
                conn.execute("INSERT INTO tiles VALUES (?, ?, ?, ?)", (z, x, (1 << z) - 1 - y, data))
    conn.commit()
    conn.close()
    return tiles


@needs_cli
def test_extract_size_matches_a_real_archive(tmp_path):
    make_mbtiles(tmp_path / "in.mbtiles", range(0, 6))
    subprocess.run(["pmtiles", "convert", str(tmp_path / "in.mbtiles"), str(tmp_path / "a.pmtiles"), "--quiet"],
                   check=True)

    tiles, size = pmtiles.extract_size(tmp_path / "a.pmtiles", (-180, -85, 180, 85), 3)

    assert tiles == 1 + 4 + 16 + 64
    assert size > 0


@needs_cli
def test_to_mbtiles_round_trips_every_tile(tmp_path):
    expected = make_mbtiles(tmp_path / "in.mbtiles")
    subprocess.run(["pmtiles", "convert", str(tmp_path / "in.mbtiles"), str(tmp_path / "a.pmtiles"), "--quiet"],
                   check=True)

    count = pmtiles.to_mbtiles(tmp_path / "a.pmtiles", tmp_path / "out.mbtiles")

    conn = sqlite3.connect(tmp_path / "out.mbtiles")
    rows = conn.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles").fetchall()
    meta = dict(conn.execute("SELECT name, value FROM metadata"))
    conn.close()
    assert count == len(expected)
    assert {(z, x, (1 << z) - 1 - row): bytes(d) for z, x, row, d in rows} == expected
    assert meta["format"] == "png"
    assert meta["attribution"] == "Test data"
