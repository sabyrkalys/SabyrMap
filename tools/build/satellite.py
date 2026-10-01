#!/usr/bin/env python3
"""Спутниковый слой (план, фаза 2.1): исходник → MBTiles WebP с пирамидой.

    satellite.py recode <in.mbtiles> <out.mbtiles> [--quality 75] [--from-zoom N] [--min-zoom 5]
    satellite.py pyramid <file.mbtiles> [--min-zoom 0] [--quality 70]
    satellite.py set-type <file.pmtiles> [--type webp]

recode
    Читает таблицу tiles исходника, JPEG/PNG → WebP (уже WebP копируется как
    есть), пишет новый MBTiles и копирует metadata (format=webp). Потоково,
    на всех ядрах, с прогрессом. Возобновляется с места остановки: повторный
    запуск с тем же out продолжает после последнего записанного тайла.
    Затем достраивает пирамиду вниз до --min-zoom: каждый родитель склеивается
    из 4 детей (Lanczos, WebP q70). Зумы ниже --from-zoom из исходника не
    берутся, а строятся заново (по умолчанию берётся всё, что есть).
    Дальше: pmtiles convert out.mbtiles satellite.pmtiles (это делает build.sh).

pyramid
    Только пирамида (вторая половина recode) для готового MBTiles WebP;
    overview.sh так достраивает z0–4 обзора мира.

set-type
    Исправляет тип тайлов в заголовке PMTiles (1 байт) по реальным байтам
    тайла. Martin берёт Content-Type из заголовка: тестовый архив Esri подписан
    jpg, а внутри WebP. Файл меняется на месте — делайте это на копии
    (cp --reflink), а не на жёсткой ссылке на исходник.
"""

import argparse
import io
import json
import os
import sqlite3
import subprocess
import sys
import time
from multiprocessing import Pool
from pathlib import Path

from PIL import Image

PAGE = 2000  # тайлов за транзакцию

# PMTiles v3: тип тайлов — байт 99 заголовка.
PMTILES_TYPE_OFFSET = 99
PMTILES_TYPES = {"mvt": 1, "png": 2, "jpg": 3, "webp": 4, "avif": 5}


def sniff(data: bytes) -> str:
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[4:12] in (b"ftypavif", b"ftypavis"):
        return "avif"
    return "unknown"


def to_webp(img: Image.Image, quality: int) -> bytes:
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA" if "transparency" in img.info or img.mode in ("LA", "PA") else "RGB")
    if img.mode == "RGBA" and img.getextrema()[3][0] == 255:
        img = img.convert("RGB")  # непрозрачный — без альфы, файл меньше
    out = io.BytesIO()
    img.save(out, "WEBP", quality=quality, method=4)
    return out.getvalue()


# --- recode -------------------------------------------------------------------

def _recode_one(job):
    key, data, quality = job
    if sniff(data) == "webp":
        return key, data
    with Image.open(io.BytesIO(data)) as img:
        img.load()
        return key, to_webp(img, quality)


def _open_out(path: Path) -> sqlite3.Connection:
    db = sqlite3.connect(path)
    db.executescript("""
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER,
                                          tile_data BLOB);
        CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row);
        -- служебное: где остановились (удаляется в конце)
        CREATE TABLE IF NOT EXISTS _build_progress (step TEXT PRIMARY KEY, z INTEGER, x INTEGER, y INTEGER);
    """)
    return db


class Progress:
    def __init__(self, label: str, total: int):
        self.label, self.total, self.done = label, total, 0
        self.start = self.last = time.monotonic()

    def add(self, n: int, force=False):
        self.done += n
        now = time.monotonic()
        if force or now - self.last >= 10:
            self.last = now
            rate = self.done / max(now - self.start, 1e-9)
            left = (self.total - self.done) / rate if rate else 0
            pct = 100 * self.done / self.total if self.total else 100
            print(f"  {self.label}: {self.done}/{self.total} ({pct:.1f}%), "
                  f"{rate:.0f} тайл/с, осталось ~{left / 60:.0f} мин", flush=True)


def recode(src: Path, out: Path, quality: int, from_zoom: int, pool: Pool) -> None:
    sdb = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    odb = _open_out(out)
    row = odb.execute("SELECT z, x, y FROM _build_progress WHERE step='recode'").fetchone()
    last = row or (-1, -1, -1)
    if row:
        print(f"  продолжаю после z{last[0]}/{last[1]}/{last[2]}", flush=True)

    total = sdb.execute("SELECT count(*) FROM tiles WHERE zoom_level >= ?", (from_zoom,)).fetchone()[0]
    done = sdb.execute(
        "SELECT count(*) FROM tiles WHERE zoom_level >= ? AND (zoom_level, tile_column, tile_row) <= (?, ?, ?)",
        (from_zoom, *last)).fetchone()[0]
    progress = Progress("WebP", total)
    progress.add(done)
    while True:
        page = sdb.execute(
            "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles "
            "WHERE zoom_level >= ? AND (zoom_level, tile_column, tile_row) > (?, ?, ?) "
            "ORDER BY zoom_level, tile_column, tile_row LIMIT ?",
            (from_zoom, *last, PAGE)).fetchall()
        if not page:
            break
        jobs = [((z, x, y), bytes(data), quality) for z, x, y, data in page]
        results = pool.map(_recode_one, jobs, chunksize=32)
        with odb:
            odb.executemany("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                            [(*key, data) for key, data in results])
            last = page[-1][:3]
            odb.execute("INSERT OR REPLACE INTO _build_progress VALUES ('recode', ?, ?, ?)", last)
        progress.add(len(page))
    progress.add(0, force=True)

    meta = dict(sdb.execute("SELECT name, value FROM metadata").fetchall())
    meta["format"] = "webp"
    with odb:
        odb.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)", meta.items())
    sdb.close()
    odb.close()


# --- pyramid ------------------------------------------------------------------

def _merge(job):
    """4 ребёнка (TMS: ряд 2r+1 — верхняя половина) → родитель того же размера."""
    (z, x, y), children, quality = job
    size = None
    imgs = {}
    for (dx, dy), data in children.items():
        img = Image.open(io.BytesIO(data))
        img.load()
        imgs[dx, dy] = img.convert("RGBA")
        size = size or img.width
    canvas = Image.new("RGBA", (2 * size, 2 * size), (0, 0, 0, 0))
    for (dx, dy), img in imgs.items():
        canvas.paste(img, (dx * size, (1 - dy) * size))
    return (z, x, y), to_webp(canvas.resize((size, size), Image.LANCZOS), quality)


def pyramid(out: Path, min_zoom: int, quality: int, pool: Pool) -> None:
    db = _open_out(out)
    present = [z for (z,) in db.execute("SELECT DISTINCT zoom_level FROM tiles ORDER BY 1")]
    if not present:
        raise SystemExit("в выходном файле нет тайлов")
    top = present[0]
    # Возобновление: зум, который уже начали строить, достраиваем заново целиком
    # (INSERT OR REPLACE), он в десятки раз меньше следующего.
    row = db.execute("SELECT z FROM _build_progress WHERE step='pyramid'").fetchone()
    if row:
        top = row[0] + 1
    for z in range(top - 1, min_zoom - 1, -1):
        parents = db.execute(
            "SELECT count(*) FROM (SELECT DISTINCT tile_column / 2, tile_row / 2 FROM tiles WHERE zoom_level = ?)",
            (z + 1,)).fetchone()[0]
        progress = Progress(f"пирамида z{z}", parents)
        with db:
            db.execute("INSERT OR REPLACE INTO _build_progress VALUES ('pyramid', ?, 0, 0)", (z,))

        def jobs():
            # По колонкам родителей: две колонки детей — короткий проход по индексу,
            # без сортировки всего зума с блобами. Pool.imap читает генератор в
            # своём потоке, поэтому соединение своё.
            rdb = sqlite3.connect(out, check_same_thread=False)
            cols = [c for (c,) in rdb.execute(
                "SELECT DISTINCT tile_column / 2 FROM tiles WHERE zoom_level = ? ORDER BY 1", (z + 1,))]
            for px in cols:
                groups = {}
                for x, y, data in rdb.execute(
                        "SELECT tile_column, tile_row, tile_data FROM tiles "
                        "WHERE zoom_level = ? AND tile_column BETWEEN ? AND ?", (z + 1, 2 * px, 2 * px + 1)):
                    groups.setdefault(y // 2, {})[x % 2, y % 2] = bytes(data)
                for py in sorted(groups):
                    yield (z, px, py), groups[py], quality
            rdb.close()

        wdb = sqlite3.connect(out)
        batch = []
        for result in pool.imap(_merge, jobs(), chunksize=16):
            batch.append(result)
            if len(batch) >= PAGE:
                _write(wdb, batch)
                progress.add(len(batch))
                batch = []
        _write(wdb, batch)
        progress.add(len(batch), force=True)
        wdb.close()

    zooms = [z for (z,) in db.execute("SELECT DISTINCT zoom_level FROM tiles ORDER BY 1")]
    with db:
        db.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)",
                       [("minzoom", str(zooms[0])), ("maxzoom", str(zooms[-1])), ("format", "webp")])
        db.execute("DROP TABLE _build_progress")
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.close()


def _write(db, batch):
    with db:
        db.executemany("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)", [(*k, d) for k, d in batch])


# --- set-type -----------------------------------------------------------------

def set_type(path: Path, wanted: str | None) -> None:
    with open(path, "rb") as f:
        header = f.read(127)
    if header[:7] != b"PMTiles" or header[7] != 3:
        raise SystemExit(f"{path}: не PMTiles v3")
    current = {v: k for k, v in PMTILES_TYPES.items()}.get(header[PMTILES_TYPE_OFFSET], "unknown")

    sample = _sample_tile(path)
    actual = sniff(sample) if sample else None
    target = wanted or actual
    if not target:
        raise SystemExit("не нашёл тайл для проверки формата; укажите --type")
    if actual and actual != target:
        raise SystemExit(f"в заголовке {current}, тайлы на самом деле {actual}, а просили {target} — не меняю")
    if current == target:
        print(f"{path}: тип тайлов уже {target}")
        return
    if os.stat(path).st_nlink > 1:
        raise SystemExit(f"{path}: у файла есть жёсткие ссылки — правка заденет и исходник. "
                         f"Сделайте копию: cp --reflink=auto")
    with open(path, "r+b") as f:
        f.seek(PMTILES_TYPE_OFFSET)
        f.write(bytes([PMTILES_TYPES[target]]))
    print(f"{path}: тип тайлов {current} → {target}")


def _sample_tile(path: Path) -> bytes | None:
    """Тайл в центре архива на макс. зуме (через CLI pmtiles)."""
    import math
    show = json.loads(subprocess.run(["pmtiles", "show", "--header-json", str(path)],
                                     check=True, capture_output=True, text=True).stdout)
    lon, lat, center_zoom = show["center"]
    for z in (show["maxzoom"], center_zoom, show["minzoom"]):
        n = 2 ** z
        x = int((lon + 180) / 360 * n)
        y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
        r = subprocess.run(["pmtiles", "tile", str(path), str(z), str(x), str(y)], capture_output=True)
        if r.returncode == 0 and r.stdout:
            return r.stdout
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    rc = sub.add_parser("recode", help="MBTiles → MBTiles WebP + пирамида")
    rc.add_argument("src", type=Path)
    rc.add_argument("out", type=Path)
    rc.add_argument("--quality", type=int, default=75, help="WebP для тайлов исходника (75)")
    rc.add_argument("--pyramid-quality", type=int, default=70, help="WebP для достроенных зумов (70)")
    rc.add_argument("--from-zoom", type=int, default=0, help="брать из исходника зумы начиная с этого")
    rc.add_argument("--min-zoom", type=int, default=5, help="достроить пирамиду вниз до этого зума (5)")
    rc.add_argument("--jobs", type=int, default=os.cpu_count())
    pr = sub.add_parser("pyramid", help="достроить зумы вниз в MBTiles WebP")
    pr.add_argument("path", type=Path)
    pr.add_argument("--min-zoom", type=int, default=0)
    pr.add_argument("--quality", type=int, default=70)
    pr.add_argument("--jobs", type=int, default=os.cpu_count())
    st = sub.add_parser("set-type", help="исправить тип тайлов в заголовке PMTiles")
    st.add_argument("path", type=Path)
    st.add_argument("--type", choices=sorted(PMTILES_TYPES), help="по умолчанию — по байтам тайла")
    args = ap.parse_args()

    if args.cmd == "set-type":
        set_type(args.path, args.type)
        return
    if args.cmd == "pyramid":
        with Pool(args.jobs) as pool:
            pyramid(args.path, args.min_zoom, args.quality, pool)
        return
    if not args.src.exists():
        raise SystemExit(f"нет файла {args.src}")
    with Pool(args.jobs) as pool:
        if not _recoded(args.out):
            print(f"WebP: {args.src} → {args.out}", flush=True)
            recode(args.src, args.out, args.quality, args.from_zoom, pool)
        print(f"Пирамида до z{args.min_zoom}", flush=True)
        pyramid(args.out, args.min_zoom, args.pyramid_quality, pool)
    print(f"Готово: {args.out}")


def _recoded(out: Path) -> bool:
    """Перекодирование закончено — metadata уже записана (её пишут в конце recode)."""
    if not out.exists():
        return False
    db = sqlite3.connect(out)
    try:
        return db.execute("SELECT 1 FROM metadata WHERE name='format' AND value='webp'").fetchone() is not None
    except sqlite3.OperationalError:
        return False
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
