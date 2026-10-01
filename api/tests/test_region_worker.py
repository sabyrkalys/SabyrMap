import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import time
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from app import worker
from app.config import settings
from app.models.map_catalog import MapCatalogEntry
from app.models.region_job import RegionJob
from app.services.regions import bbox_geometry
from tests.map_helpers import map_server, seeded, style  # noqa: F401
from tests.test_pmtiles import make_mbtiles, needs_cli

BBOX = (76.95, 43.03, 77.01, 43.07)


def fake_fetch(path: str) -> bytes:
    return f"fetched:{path}".encode()


def test_offline_style_points_sources_at_region_files():
    offline = worker.offline_style(
        style("hybrid-day", hybrid=True), {"osm": "osm.mbtiles", "satellite": "satellite.mbtiles",
                                           "overview": "overview.mbtiles"}
    )

    assert offline["sources"]["osm"] == {"type": "vector", "maxzoom": 14,
                                         "url": "mbtiles://{{REGION_DIR}}/osm.mbtiles"}
    assert offline["sources"]["satellite"]["url"] == "mbtiles://{{REGION_DIR}}/satellite.mbtiles"
    assert offline["glyphs"] == "file://{{REGION_DIR}}/fonts/{fontstack}/{range}.pbf"
    assert offline["sprite"] == "file://{{REGION_DIR}}/sprites/sabyr"
    assert "http" not in json.dumps(offline)


def test_offline_style_drops_sources_with_no_tiles_in_the_region():
    offline = worker.offline_style(style("hybrid-day", hybrid=True),
                                   {"osm": "osm.mbtiles", "overview": "overview.mbtiles"})

    assert "satellite" not in offline["sources"]
    assert all(layer.get("source") != "satellite" for layer in offline["layers"])


def test_style_zip_has_style_glyphs_and_sprite(tmp_path):
    out = worker.build_style_zip(style("vector-day", hybrid=False), {"osm": "osm.mbtiles",
                                                                     "overview": "overview.mbtiles"},
                                 tmp_path / "style.zip", fake_fetch)

    names = set(zipfile.ZipFile(out).namelist())
    assert "style.json" in names
    assert "fonts/Noto Sans Regular/1024-1279.pbf" in names
    assert "fonts/Noto Sans Bold/0-255.pbf" in names
    assert {"sprites/sabyr.json", "sprites/sabyr.png", "sprites/sabyr@2x.json", "sprites/sabyr@2x.png"} <= names
    assert zipfile.ZipFile(out).read("fonts/Noto Sans Regular/1024-1279.pbf") == \
        b"fetched:font/Noto%20Sans%20Regular/1024-1279"


def _job(db, user_id_email="worker@example.test", **fields):
    from app.services.organizations import create_personal_organization_and_owner

    user = create_personal_organization_and_owner(db, email=user_id_email, password_hash="x")
    job = RegionJob(
        user_id=user.id, map_id="server-hybrid-day", max_zoom=12, version="v1",
        bbox=bbox_geometry(BBOX),
        status="queued", progress=0.0, storage_dir=uuid.uuid4().hex, **fields,
    )
    db.add(job)
    db.flush()
    return job


def test_claim_takes_the_oldest_queued_job(seeded):
    job = _job(seeded)

    claimed = worker.claim_job(seeded)

    assert claimed.id == job.id
    assert claimed.status == "running"
    assert worker.claim_job(seeded) is None


def test_interrupted_jobs_are_requeued(seeded):
    job = _job(seeded)
    job.status = "running"
    seeded.flush()

    assert worker.requeue_interrupted(seeded) == 1
    seeded.refresh(job)
    assert job.status == "queued"


def _old_folder(root: Path, name: str) -> Path:
    folder = root / name
    folder.mkdir()
    (folder / "x.mbtiles").write_bytes(b"x")
    old = time.time() - 3600
    os.utime(folder, (old, old))
    return folder


def test_cleanup_expires_regions_and_deletes_unused_folders(seeded, map_server):
    root = Path(settings.REGIONS_PATH)
    live = _job(seeded, "live@example.test", expires_at=datetime.now(timezone.utc) + timedelta(hours=1))
    live.status = "ready"
    expired = _job(seeded, "expired@example.test", expires_at=datetime.now(timezone.utc) - timedelta(minutes=1))
    expired.status = "ready"
    seeded.flush()
    _old_folder(root, live.storage_dir)
    _old_folder(root, expired.storage_dir)
    _old_folder(root, "orphan")
    fresh = root / "just-created"
    fresh.mkdir()

    removed = worker.cleanup(seeded)

    seeded.refresh(expired)
    assert expired.status == "expired"
    assert sorted(removed) == sorted([expired.storage_dir, "orphan"])
    assert (root / live.storage_dir).exists()
    assert fresh.exists()


def test_shared_folder_survives_while_another_job_uses_it(seeded, map_server):
    root = Path(settings.REGIONS_PATH)
    a = _job(seeded, "share-a@example.test", expires_at=datetime.now(timezone.utc) - timedelta(minutes=1))
    b = _job(seeded, "share-b@example.test", expires_at=datetime.now(timezone.utc) + timedelta(hours=1))
    a.status = b.status = "ready"
    b.storage_dir = a.storage_dir
    seeded.flush()
    _old_folder(root, a.storage_dir)

    assert worker.cleanup(seeded) == []


def _real_archives(tiles_v1: Path, tmp_path: Path) -> None:
    for name, zooms in (("satellite", range(0, 7)), ("osm", range(0, 6)), ("overview", range(0, 4))):
        mb = tmp_path / f"{name}.mbtiles"
        make_mbtiles(mb, zooms)
        (tiles_v1 / f"{name}.pmtiles").unlink()
        subprocess.run(["pmtiles", "convert", str(mb), str(tiles_v1 / f"{name}.pmtiles"), "--quiet"], check=True)


@needs_cli
def test_build_region_cuts_every_archive_and_writes_a_manifest(seeded, map_server):
    _real_archives(map_server / "tiles" / "v1", map_server)
    entry = seeded.get(MapCatalogEntry, "server-hybrid-day")
    out = Path(settings.REGIONS_PATH) / "r1"

    files = worker.build_region(entry, BBOX, 5, out, fetch=fake_fetch)

    names = [f["name"] for f in files]
    assert names == ["osm.mbtiles", "overview.mbtiles", "satellite.mbtiles", "style.zip", "manifest.json"]
    for f in files:
        assert hashlib.sha256((out / f["name"]).read_bytes()).hexdigest() == f["sha256"]
    conn = sqlite3.connect(out / "satellite.mbtiles")
    zooms = [z for (z,) in conn.execute("SELECT DISTINCT zoom_level FROM tiles ORDER BY 1")]
    # z5 tile over Almaty: x=42, y=23 (TMS row 8); stored data says which tile it is.
    data = conn.execute("SELECT tile_data FROM tiles WHERE zoom_level=5").fetchall()
    conn.close()
    assert zooms == [0, 1, 2, 3, 4, 5]
    assert [bytes(d) for (d,) in data] == [b"5/22/11"]
    manifest = json.loads((out / "manifest.json").read_text())
    assert manifest["map_id"] == "server-hybrid-day"
    assert [f["name"] for f in manifest["files"]] == names[:-1]
    assert not list(out.glob("*.pmtiles"))


@needs_cli
def test_process_job_marks_ready_and_failed(seeded, map_server):
    _real_archives(map_server / "tiles" / "v1", map_server)
    ok = _job(seeded, "proc-ok@example.test")
    ok.max_zoom = 4
    seeded.flush()

    worker.process_job(seeded, ok, fetch=fake_fetch)

    seeded.refresh(ok)
    assert ok.status == "ready"
    assert ok.progress == 1.0
    assert ok.expires_at > datetime.now(timezone.utc)
    assert ok.size_bytes == sum(f["size"] for f in ok.files)

    (map_server / "tiles" / "v1" / "osm.pmtiles").write_bytes(b"broken")
    bad = _job(seeded, "proc-bad@example.test")
    seeded.commit()  # claim_job commits the job before processing
    worker.process_job(seeded, bad, fetch=fake_fetch)
    seeded.refresh(bad)
    assert bad.status == "failed"
    assert bad.error
    assert not (Path(settings.REGIONS_PATH) / bad.storage_dir).exists()
