"""PMTiles → MBTiles для небольших архивов (встроенная базовая карта APK).

    python3 pmtiles_to_mbtiles.py <in.pmtiles> <out.mbtiles> [--max-zoom 5]

Тайлы берёт CLI `pmtiles tile` (есть в образе sabyrmap-api), поэтому
годится только для маленьких пирамид: каждый тайл — отдельный вызов.
MBTiles хранит строки в схеме TMS (y снизу), PMTiles — XYZ.
"""
import argparse
import json
import sqlite3
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("src", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--max-zoom", type=int)
    args = parser.parse_args()

    header = json.loads(subprocess.run(["pmtiles", "show", "--header-json", str(args.src)],
                                       capture_output=True, check=True, text=True).stdout)
    meta = json.loads(subprocess.run(["pmtiles", "show", "--metadata", str(args.src)],
                                     capture_output=True, check=True, text=True).stdout or "{}")
    min_zoom = header["minzoom"]
    max_zoom = header["maxzoom"] if args.max_zoom is None else min(args.max_zoom, header["maxzoom"])
    tile_type = {"mvt": "pbf"}.get(header["tile_type"], header["tile_type"])

    args.out.unlink(missing_ok=True)
    db = sqlite3.connect(args.out)
    db.executescript("""
        CREATE TABLE metadata (name TEXT, value TEXT);
        CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    """)
    db.executemany("INSERT INTO metadata VALUES (?, ?)", [
        ("name", meta.get("name", args.out.stem)),
        ("format", tile_type),
        ("type", "baselayer"),
        ("minzoom", str(min_zoom)),
        ("maxzoom", str(max_zoom)),
        ("bounds", ",".join(str(b) for b in header["bounds"])),
        ("description", meta.get("description", "")),
        ("attribution", meta.get("attribution", "Natural Earth")),
    ])
    count = 0
    for z in range(min_zoom, max_zoom + 1):
        for x in range(2 ** z):
            for y in range(2 ** z):
                r = subprocess.run(["pmtiles", "tile", str(args.src), str(z), str(x), str(y)], capture_output=True)
                if r.returncode != 0 or not r.stdout:
                    continue
                db.execute("INSERT INTO tiles VALUES (?, ?, ?, ?)", (z, x, (2 ** z - 1) - y, r.stdout))
                count += 1
    db.commit()
    db.close()
    print(f"{count} тайлов z{min_zoom}–{max_zoom} → {args.out}")


if __name__ == "__main__":
    main()
