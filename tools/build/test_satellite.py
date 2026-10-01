"""Тесты satellite.py. Запуск в образе сборки:

    docker run --rm -v "$PWD/tools/build:/build" sabyrmap-build python3 -m unittest -v test_satellite
"""

import io
import os
import sqlite3
import subprocess
import tempfile
import unittest
from multiprocessing import Pool
from pathlib import Path

from PIL import Image

import satellite

# Цвет каждого ребёнка z1 в координатах XYZ (x, y): y=0 — верх.
COLORS = {(0, 0): (255, 0, 0), (1, 0): (0, 255, 0), (0, 1): (0, 0, 255), (1, 1): (255, 255, 0)}


def jpeg(color, size=256):
    out = io.BytesIO()
    Image.new("RGB", (size, size), color).save(out, "JPEG", quality=95)
    return out.getvalue()


def make_source(path: Path):
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index on tiles (zoom_level, tile_column, tile_row);
    """)
    db.executemany("INSERT INTO metadata VALUES (?, ?)",
                   [("format", "jpg"), ("name", "test"), ("minzoom", "1"), ("maxzoom", "1")])
    # MBTiles хранит ряды в TMS: tms_row = 2^z - 1 - y.
    db.executemany("INSERT INTO tiles VALUES (1, ?, ?, ?)",
                   [(x, 1 - y, jpeg(c)) for (x, y), c in COLORS.items()])
    db.commit()
    db.close()


class RecodeTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.src, self.out = self.dir / "src.mbtiles", self.dir / "out.mbtiles"
        make_source(self.src)
        self.pool = Pool(2)

    def tearDown(self):
        self.pool.close()
        self.pool.join()

    def build(self):
        satellite.recode(self.src, self.out, 75, 0, self.pool)
        satellite.pyramid(self.out, 0, 70, self.pool)
        return sqlite3.connect(self.out)

    def test_tiles_become_webp_and_metadata_follows(self):
        db = self.build()
        for (data,) in db.execute("SELECT tile_data FROM tiles"):
            self.assertEqual(satellite.sniff(data), "webp")
        meta = dict(db.execute("SELECT name, value FROM metadata"))
        self.assertEqual((meta["format"], meta["minzoom"], meta["maxzoom"], meta["name"]), ("webp", "0", "1", "test"))
        tables = {n for (n,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertNotIn("_build_progress", tables)

    def test_parent_puts_each_child_in_its_quadrant(self):
        db = self.build()
        (data,) = db.execute("SELECT tile_data FROM tiles WHERE zoom_level = 0").fetchone()
        img = Image.open(io.BytesIO(data)).convert("RGB")
        self.assertEqual(img.size, (256, 256))
        for (x, y), color in COLORS.items():
            got = img.getpixel((64 + 128 * x, 64 + 128 * y))
            self.assertTrue(all(abs(a - b) < 40 for a, b in zip(got, color)), f"{(x, y)}: {got} != {color}")

    def test_resume_continues_after_the_last_written_tile(self):
        db = satellite._open_out(self.out)
        with db:
            # порядок (колонка, ряд): (0,0), (0,1), (1,0), (1,1) — первые два «уже сделаны»
            db.execute("INSERT INTO _build_progress VALUES ('recode', 1, 0, 1)")
        db.close()
        satellite.recode(self.src, self.out, 75, 0, self.pool)
        rows = sqlite3.connect(self.out).execute("SELECT tile_column, tile_row FROM tiles").fetchall()
        self.assertEqual(sorted(rows), [(1, 0), (1, 1)])

    def test_from_zoom_rebuilds_lower_zooms_instead_of_copying(self):
        db = sqlite3.connect(self.src)
        db.execute("INSERT INTO tiles VALUES (0, 0, 0, ?)", (jpeg((0, 0, 0)),))  # «плохой» z0
        db.commit()
        satellite.recode(self.src, self.out, 75, 1, self.pool)
        satellite.pyramid(self.out, 0, 70, self.pool)
        (data,) = sqlite3.connect(self.out).execute("SELECT tile_data FROM tiles WHERE zoom_level = 0").fetchone()
        self.assertNotEqual(Image.open(io.BytesIO(data)).convert("RGB").getpixel((64, 64)), (0, 0, 0))


class SetTypeTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        src = self.dir / "src.mbtiles"
        make_source(src)
        sqlite3.connect(src).execute("UPDATE metadata SET value='jpg' WHERE name='format'")
        self.pmtiles = self.dir / "sat.pmtiles"
        subprocess.run(["pmtiles", "convert", str(src), str(self.pmtiles)], check=True, capture_output=True)

    def header_type(self):
        with open(self.pmtiles, "rb") as f:
            return f.read(127)[satellite.PMTILES_TYPE_OFFSET]

    def test_already_matching_type_is_left_alone(self):
        satellite.set_type(self.pmtiles, None)
        self.assertEqual(self.header_type(), satellite.PMTILES_TYPES["jpg"])

    def test_refuses_a_type_the_tiles_do_not_have(self):
        with self.assertRaises(SystemExit):
            satellite.set_type(self.pmtiles, "webp")

    def test_refuses_to_patch_a_hardlinked_file(self):
        with open(self.pmtiles, "r+b") as f:  # подписать как webp, хотя внутри jpg
            f.seek(satellite.PMTILES_TYPE_OFFSET)
            f.write(bytes([satellite.PMTILES_TYPES["webp"]]))
        os.link(self.pmtiles, self.dir / "link.pmtiles")
        with self.assertRaises(SystemExit):
            satellite.set_type(self.pmtiles, None)
        os.unlink(self.dir / "link.pmtiles")
        satellite.set_type(self.pmtiles, None)
        self.assertEqual(self.header_type(), satellite.PMTILES_TYPES["jpg"])


if __name__ == "__main__":
    unittest.main()
