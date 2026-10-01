"""Reading PMTiles v3 archives: the header, every tile (to turn an extracted
region into MBTiles, which the phone opens), and region sizes.

The `pmtiles` CLI cuts regions out of the big archives (`pmtiles extract`) but
only converts MBTiles → PMTiles, so the reverse step lives here. Regions are at
most a few hundred MB, so reading one fully is fine.

Spec: https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md
"""

import gzip
import json
import re
import sqlite3
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterator

HEADER_SIZE = 127

_COMPRESSION_NONE = 1
_COMPRESSION_GZIP = 2

TILE_TYPES = {1: "mvt", 2: "png", 3: "jpg", 4: "webp", 5: "avif"}
# MBTiles `format` metadata for each tile type.
_MBTILES_FORMAT = {"mvt": "pbf", "png": "png", "jpg": "jpg", "webp": "webp", "avif": "avif"}


class PMTilesError(ValueError):
    pass


@dataclass(frozen=True)
class Header:
    root_dir_offset: int
    root_dir_length: int
    metadata_offset: int
    metadata_length: int
    leaf_dir_offset: int
    leaf_dir_length: int
    tile_data_offset: int
    tile_data_length: int
    addressed_tiles: int
    tile_entries: int
    tile_contents: int
    internal_compression: int
    tile_compression: int
    tile_type: str
    min_zoom: int
    max_zoom: int
    bounds: tuple[float, float, float, float]  # west, south, east, north
    center_zoom: int
    center: tuple[float, float]  # lon, lat


def parse_header(data: bytes) -> Header:
    if len(data) < HEADER_SIZE or data[:7] != b"PMTiles":
        raise PMTilesError("not a PMTiles archive")
    if data[7] != 3:
        raise PMTilesError(f"unsupported PMTiles version {data[7]}")
    u64 = struct.unpack_from("<11Q", data, 8)
    (_clustered, internal_c, tile_c, tile_type, min_z, max_z) = struct.unpack_from("<6B", data, 96)
    min_lon, min_lat, max_lon, max_lat = struct.unpack_from("<4i", data, 102)
    (center_z,) = struct.unpack_from("<B", data, 118)
    center_lon, center_lat = struct.unpack_from("<2i", data, 119)
    return Header(
        *u64,
        internal_compression=internal_c,
        tile_compression=tile_c,
        tile_type=TILE_TYPES.get(tile_type, "unknown"),
        min_zoom=min_z,
        max_zoom=max_z,
        bounds=(min_lon / 1e7, min_lat / 1e7, max_lon / 1e7, max_lat / 1e7),
        center_zoom=center_z,
        center=(center_lon / 1e7, center_lat / 1e7),
    )


def read_header(path: str | Path) -> Header:
    with open(path, "rb") as f:
        return parse_header(f.read(HEADER_SIZE))


# --- Tile ids (Hilbert curve per zoom, zooms stacked) ---------------------


def _rotate(n: int, x: int, y: int, rx: int, ry: int) -> tuple[int, int]:
    if ry == 0:
        if rx == 1:
            x, y = n - 1 - x, n - 1 - y
        x, y = y, x
    return x, y


def zxy_to_tileid(z: int, x: int, y: int) -> int:
    acc = ((1 << (2 * z)) - 1) // 3
    n = 1 << z
    d = 0
    s = n >> 1
    while s > 0:
        rx = 1 if x & s else 0
        ry = 1 if y & s else 0
        d += s * s * ((3 * rx) ^ ry)
        x, y = _rotate(n, x, y, rx, ry)
        s >>= 1
    return acc + d


def tileid_to_zxy(tile_id: int) -> tuple[int, int, int]:
    z = 0
    acc = 0
    while True:
        count = 1 << (2 * z)
        if tile_id < acc + count:
            break
        acc += count
        z += 1
    t = tile_id - acc
    x = y = 0
    s = 1
    n = 1 << z
    while s < n:
        rx = 1 & (t // 2)
        ry = 1 & (t ^ rx)
        x, y = _rotate(s, x, y, rx, ry)
        x += s * rx
        y += s * ry
        t //= 4
        s *= 2
    return z, x, y


# --- Directories ------------------------------------------------------------


def _decompress(data: bytes, compression: int) -> bytes:
    if compression == _COMPRESSION_GZIP:
        return gzip.decompress(data)
    if compression in (_COMPRESSION_NONE, 0):
        return data
    raise PMTilesError(f"unsupported internal compression {compression}")


def _read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        byte = buf[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, pos
        shift += 7


@dataclass(frozen=True)
class _Entry:
    tile_id: int
    offset: int
    length: int
    run_length: int


def _parse_directory(buf: bytes) -> list[_Entry]:
    pos = 0
    count, pos = _read_varint(buf, pos)
    ids, runs, lengths, offsets = [], [], [], []
    last = 0
    for _ in range(count):
        delta, pos = _read_varint(buf, pos)
        last += delta
        ids.append(last)
    for _ in range(count):
        v, pos = _read_varint(buf, pos)
        runs.append(v)
    for _ in range(count):
        v, pos = _read_varint(buf, pos)
        lengths.append(v)
    for i in range(count):
        v, pos = _read_varint(buf, pos)
        if v == 0 and i > 0:
            offsets.append(offsets[i - 1] + lengths[i - 1])
        else:
            offsets.append(v - 1)
    return [_Entry(ids[i], offsets[i], lengths[i], runs[i]) for i in range(count)]


def _read_at(f: BinaryIO, offset: int, length: int) -> bytes:
    f.seek(offset)
    return f.read(length)


def iter_tiles(path: str | Path) -> Iterator[tuple[int, int, int, bytes]]:
    """Yields (z, x, y, data) for every addressed tile. Data is stored as in
    the archive (vector tiles stay gzip-compressed, as MBTiles expects)."""
    with open(path, "rb") as f:
        header = parse_header(f.read(HEADER_SIZE))

        def walk(offset: int, length: int, leaf: bool) -> Iterator[tuple[int, int, int, bytes]]:
            base = header.leaf_dir_offset if leaf else header.root_dir_offset
            raw = _read_at(f, base + offset if leaf else offset, length)
            for entry in _parse_directory(_decompress(raw, header.internal_compression)):
                if entry.run_length == 0:
                    yield from walk(entry.offset, entry.length, True)
                    continue
                data = _read_at(f, header.tile_data_offset + entry.offset, entry.length)
                for tile_id in range(entry.tile_id, entry.tile_id + entry.run_length):
                    yield (*tileid_to_zxy(tile_id), data)

        yield from walk(header.root_dir_offset, header.root_dir_length, False)


def read_metadata(path: str | Path) -> dict:
    with open(path, "rb") as f:
        header = parse_header(f.read(HEADER_SIZE))
        raw = _read_at(f, header.metadata_offset, header.metadata_length)
    if not raw:
        return {}
    return json.loads(_decompress(raw, header.internal_compression))


def sniff_format(data: bytes) -> str | None:
    """Raster format from the image bytes. Archive headers can be wrong (the
    v1 satellite says jpg but holds WebP), the bytes are not."""
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    return None


def to_mbtiles(src: str | Path, dst: str | Path) -> int:
    """Writes every tile of a PMTiles archive into a new MBTiles file.
    Returns the number of tiles written."""
    header = read_header(src)
    meta = read_metadata(src)
    dst = Path(dst)
    dst.unlink(missing_ok=True)
    conn = sqlite3.connect(dst)
    try:
        conn.executescript(
            """
            CREATE TABLE metadata (name TEXT, value TEXT);
            CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER,
                                tile_row INTEGER, tile_data BLOB);
            """
        )
        west, south, east, north = header.bounds
        fields = {
            "name": meta.get("name", Path(src).stem),
            "format": _MBTILES_FORMAT.get(header.tile_type, header.tile_type),
            "type": meta.get("type", "baselayer"),
            "minzoom": str(header.min_zoom),
            "maxzoom": str(header.max_zoom),
            "bounds": f"{west},{south},{east},{north}",
            "center": f"{header.center[0]},{header.center[1]},{header.center_zoom}",
        }
        if "attribution" in meta:
            fields["attribution"] = meta["attribution"]
        if "vector_layers" in meta:
            fields["json"] = json.dumps({"vector_layers": meta["vector_layers"]})
        count = 0
        batch = []
        for z, x, y, data in iter_tiles(src):
            if count == 0 and not batch:
                fields["format"] = sniff_format(data) or fields["format"]
            # MBTiles rows are TMS: y counts from the south.
            batch.append((z, x, (1 << z) - 1 - y, data))
            if len(batch) >= 500:
                conn.executemany("INSERT INTO tiles VALUES (?, ?, ?, ?)", batch)
                count += len(batch)
                batch.clear()
        conn.executemany("INSERT INTO tiles VALUES (?, ?, ?, ?)", batch)
        count += len(batch)
        conn.executemany("INSERT INTO metadata VALUES (?, ?)", fields.items())
        conn.execute("CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)")
        conn.commit()
    finally:
        conn.close()
    return count


# --- Region sizes -----------------------------------------------------------

_UNITS = {"B": 1, "kB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
_FETCHING = re.compile(r"fetching (\d+) tiles")
_ARCHIVE_SIZE = re.compile(r"archive size of ([\d.]+) (B|kB|MB|GB|TB)")


def extract_size(path: str | Path, bbox: tuple[float, float, float, float], max_zoom: int) -> tuple[int, int]:
    """(tiles, bytes) that `pmtiles extract` would write for bbox up to
    max_zoom, from the archive's directories only (--dry-run: milliseconds
    even for a 100 GB archive). The size is rounded to 2–3 digits by the CLI."""
    with tempfile.TemporaryDirectory() as tmp:
        result = subprocess.run(
            [
                "pmtiles", "extract", str(path), str(Path(tmp) / "dry-run.pmtiles"), "--dry-run",
                "--bbox=" + ",".join(f"{v:.6f}" for v in bbox),
                f"--maxzoom={max_zoom}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    output = result.stdout + result.stderr
    tiles = _FETCHING.search(output)
    size = _ARCHIVE_SIZE.search(output)
    if tiles is None or size is None:
        raise PMTilesError(f"unexpected pmtiles extract output: {output[-500:]}")
    return int(tiles.group(1)), int(float(size.group(1)) * _UNITS[size.group(2)])


def intersect_bbox(
    a: tuple[float, float, float, float], b: tuple[float, float, float, float]
) -> tuple[float, float, float, float] | None:
    west, south = max(a[0], b[0]), max(a[1], b[1])
    east, north = min(a[2], b[2]), min(a[3], b[3])
    if west >= east or south >= north:
        return None
    return west, south, east, north
