"""Offline region worker.

The queue is the region_jobs table (SELECT … FOR UPDATE SKIP LOCKED), no
broker. For each job, in a fresh folder under REGIONS_PATH/<storage_dir>:

  pmtiles extract <tileset>.pmtiles → app.services.pmtiles.to_mbtiles → <tileset>.mbtiles
  style.zip   (vector maps): offline style.json + glyph PBFs + sprite
  manifest.json with sizes and sha256

Tiles are copied as they are, never re-encoded. Every 15 minutes expired
regions are marked and folders no live job points at are deleted.

Run: python -m app.worker
"""

import hashlib
import json
import shutil
import subprocess
import threading
import time
import traceback
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models.map_catalog import MapCatalogEntry
from app.models.region_job import RegionJob
from app.services import maps, pmtiles
from app.services.regions import ACTIVE_STATUSES, job_bbox

POLL_SECONDS = 3
CLEANUP_SECONDS = 15 * 60
# A folder nobody points at is deleted only after this long, so a job that is
# just being created is never swept away.
ORPHAN_GRACE = timedelta(minutes=10)

# Glyph ranges shipped offline: Latin, Latin-1/Extended, Cyrillic (with
# Kazakh letters) and its supplement, general punctuation.
FONT_RANGES = ("0-255", "256-511", "1024-1279", "1280-1535", "8192-8447")
SPRITE_FILES = ("{id}.json", "{id}.png", "{id}@2x.json", "{id}@2x.png")

# The app replaces this with the region's folder on the phone.
REGION_DIR = "{{REGION_DIR}}"

Fetch = Callable[[str], bytes]


def log(message: str) -> None:
    print(f"[worker] {message}", flush=True)


def http_fetch(path: str) -> bytes:
    with urllib.request.urlopen(f"{settings.MARTIN_URL.rstrip('/')}/{path}", timeout=60) as r:
        return r.read()


# --- Queue ---------------------------------------------------------------


def claim_job(db: Session) -> RegionJob | None:
    row = db.execute(
        text(
            """
            UPDATE region_jobs SET status = 'running', progress = 0
            WHERE id = (
                SELECT id FROM region_jobs WHERE status = 'queued'
                ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1
            )
            RETURNING id
            """
        )
    ).first()
    db.commit()
    return db.get(RegionJob, row[0]) if row else None


def requeue_interrupted(db: Session) -> int:
    """Jobs left 'running' by a stopped worker go back to the queue. Only
    safe with one worker container (compose runs one)."""
    count = db.execute(text("UPDATE region_jobs SET status = 'queued' WHERE status = 'running'")).rowcount
    db.commit()
    return count


def _set_progress(db: Session, job: RegionJob, value: float) -> None:
    job.progress = round(value, 3)
    db.commit()


# --- Building a region ------------------------------------------------------


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_tileset(src: Path, out_dir: Path, tileset: str, bbox, max_zoom: int) -> Path | None:
    """Cuts bbox out of an archive into <tileset>.mbtiles; None when the
    archive has nothing there."""
    header = pmtiles.read_header(src)
    area = pmtiles.intersect_bbox(bbox, header.bounds)
    top = min(max_zoom, header.max_zoom)
    if area is None or top < header.min_zoom:
        return None
    part = out_dir / f"{tileset}.pmtiles"
    subprocess.run(
        [
            "pmtiles", "extract", str(src), str(part), "--quiet",
            "--bbox=" + ",".join(f"{v:.6f}" for v in area),
            f"--maxzoom={top}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    out = out_dir / f"{tileset}.mbtiles"
    pmtiles.to_mbtiles(part, out)
    part.unlink()
    return out


def _fontstacks(style: dict) -> set[str]:
    stacks = set()
    for layer in style.get("layers", []):
        fonts = layer.get("layout", {}).get("text-font")
        if isinstance(fonts, list) and all(isinstance(f, str) for f in fonts):
            stacks.add(",".join(fonts))
    return stacks


def offline_style(style: dict, extracted: dict[str, str]) -> dict:
    """The published style with Martin URLs replaced by files in the region
    folder. `extracted` maps tileset name → mbtiles file name; sources (and
    their layers) with no tiles in the region are dropped."""
    style = json.loads(json.dumps(style))
    source_tilesets = maps.style_tilesets(style)
    dropped = set()
    for source_id, source in list(style["sources"].items()):
        tileset = source_tilesets.get(source_id)
        if tileset is None:
            continue
        if tileset not in extracted:
            del style["sources"][source_id]
            dropped.add(source_id)
            continue
        source.pop("tiles", None)
        source["url"] = f"mbtiles://{REGION_DIR}/{extracted[tileset]}"
    style["layers"] = [l for l in style["layers"] if l.get("source") not in dropped]
    style["glyphs"] = f"file://{REGION_DIR}/fonts/{{fontstack}}/{{range}}.pbf"
    if "sprite" in style:
        sprite_id = str(style["sprite"]).rstrip("/").rsplit("/", 1)[-1]
        style["sprite"] = f"file://{REGION_DIR}/sprites/{sprite_id}"
    return style


def build_style_zip(style: dict, extracted: dict[str, str], out: Path, fetch: Fetch) -> Path:
    offline = offline_style(style, extracted)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("style.json", json.dumps(offline, ensure_ascii=False))
        for stack in sorted(_fontstacks(style)):
            for rng in FONT_RANGES:
                data = fetch(f"font/{urllib.parse.quote(stack)}/{rng}")
                z.writestr(f"fonts/{stack}/{rng}.pbf", data)
        if "sprite" in style:
            sprite_id = str(style["sprite"]).rstrip("/").rsplit("/", 1)[-1]
            for pattern in SPRITE_FILES:
                name = pattern.format(id=sprite_id)
                z.writestr(f"sprites/{name}", fetch(f"sprite/{name}"))
    return out


def build_region(
    entry: MapCatalogEntry,
    bbox,
    max_zoom: int,
    out_dir: Path,
    *,
    fetch: Fetch = http_fetch,
    on_progress: Callable[[float], None] = lambda _: None,
) -> list[dict]:
    """Writes the region's files into out_dir; returns [{name, size, sha256}]
    including manifest.json (last)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    tilesets = maps.tilesets_for(entry)
    extracted: dict[str, str] = {}
    for i, tileset in enumerate(tilesets):
        path = extract_tileset(maps.tileset_path(entry.version, tileset), out_dir, tileset, bbox, max_zoom)
        if path is not None:
            extracted[tileset] = path.name
        on_progress((i + 1) / (len(tilesets) + 1))
    if not extracted:
        raise ValueError("В этой области нет данных карты")
    names = list(extracted.values())
    if maps.is_style(entry):
        build_style_zip(maps.load_style(entry), extracted, out_dir / "style.zip", fetch)
        names.append("style.zip")
    files = [{"name": n, "size": (out_dir / n).stat().st_size, "sha256": _sha256(out_dir / n)} for n in names]
    manifest = {
        "map_id": entry.id,
        "map_name": entry.name,
        "version": entry.version,
        "format": entry.format,
        "bbox": list(bbox),
        "max_zoom": max_zoom,
        "attribution": entry.attribution,
        "files": files,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    files.append({"name": "manifest.json", "size": manifest_path.stat().st_size, "sha256": _sha256(manifest_path)})
    return files


def process_job(db: Session, job: RegionJob, fetch: Fetch = http_fetch) -> None:
    out_dir = Path(settings.REGIONS_PATH) / job.storage_dir
    log(f"job {job.id}: {job.map_id} z{job.max_zoom} {job_bbox(job)}")
    try:
        entry = db.get(MapCatalogEntry, job.map_id)
        files = build_region(
            entry,
            job_bbox(job),
            job.max_zoom,
            out_dir,
            fetch=fetch,
            on_progress=lambda v: _set_progress(db, job, v),
        )
    except Exception as e:
        db.rollback()
        shutil.rmtree(out_dir, ignore_errors=True)
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else str(e)
        log(f"job {job.id} failed: {detail}\n{traceback.format_exc()}")
        job = db.get(RegionJob, job.id)
        if job is not None:  # deleted by the user meanwhile
            job.status = "failed"
            job.error = detail[:2000] or type(e).__name__
            db.commit()
        return
    now = datetime.now(timezone.utc)
    job = db.get(RegionJob, job.id)
    if job is None:
        shutil.rmtree(out_dir, ignore_errors=True)
        return
    job.status = "ready"
    job.progress = 1.0
    job.files = files
    job.size_bytes = sum(f["size"] for f in files)
    job.ready_at = now
    job.expires_at = now + timedelta(hours=settings.REGION_TTL_HOURS)
    db.commit()
    log(f"job {job.id} ready: {job.size_bytes / 1e6:.1f} MB")


# --- Cleanup ----------------------------------------------------------------


def cleanup(db: Session, now: datetime | None = None) -> list[str]:
    """Marks expired regions and deletes folders no queued/running/ready job
    points at. Returns the deleted folder names."""
    now = now or datetime.now(timezone.utc)
    db.query(RegionJob).filter(RegionJob.status == "ready", RegionJob.expires_at <= now).update(
        {RegionJob.status: "expired"}, synchronize_session=False
    )
    db.commit()
    live = {
        d for (d,) in db.query(RegionJob.storage_dir).filter(RegionJob.status.in_(ACTIVE_STATUSES)).distinct()
    }
    removed = []
    root = Path(settings.REGIONS_PATH)
    if not root.exists():
        return removed
    for folder in root.iterdir():
        if not folder.is_dir() or folder.name in live:
            continue
        modified = datetime.fromtimestamp(folder.stat().st_mtime, timezone.utc)
        if now - modified < ORPHAN_GRACE:
            continue
        shutil.rmtree(folder, ignore_errors=True)
        removed.append(folder.name)
    return removed


# --- Main loop ----------------------------------------------------------------


def _runner(stop: threading.Event) -> None:
    while not stop.is_set():
        db = SessionLocal()
        try:
            job = claim_job(db)
            if job is None:
                stop.wait(POLL_SECONDS)
                continue
            process_job(db, job)
        except Exception:
            log("runner error:\n" + traceback.format_exc())
            stop.wait(POLL_SECONDS)
        finally:
            db.close()


def main() -> None:
    db = SessionLocal()
    try:
        requeued = requeue_interrupted(db)
    finally:
        db.close()
    log(f"started: {settings.REGION_MAX_PARALLEL} parallel jobs, requeued {requeued}")
    stop = threading.Event()
    for i in range(settings.REGION_MAX_PARALLEL):
        threading.Thread(target=_runner, args=(stop,), name=f"region-{i}", daemon=True).start()
    while True:
        db = SessionLocal()
        try:
            removed = cleanup(db)
            if removed:
                log(f"cleanup: removed {len(removed)} folders")
        except Exception:
            log("cleanup error:\n" + traceback.format_exc())
        finally:
            db.close()
        time.sleep(CLEANUP_SECONDS)


if __name__ == "__main__":
    main()
