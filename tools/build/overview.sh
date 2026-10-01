#!/usr/bin/env bash
# Обзорная карта мира z0–5 (план, фаза 2.3): Natural Earth I с отмывкой рельефа
# (общественное достояние) → Web Mercator → MBTiles WebP → overview.pmtiles.
#
#   tools/build/overview.sh <версия>          # → $TILES_DIR/<версия>/overview.pmtiles
#
# GDAL и pmtiles запускаются в контейнерах, на хосте нужен только docker.
set -euo pipefail

ver=${1:?версия, напр. v1}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
if [[ -z "${TILES_DIR:-}" && -f "$root/.env" ]]; then
  TILES_DIR=$(grep -E '^TILES_DIR=' "$root/.env" | tail -1 | cut -d= -f2-)
fi
: "${TILES_DIR:?TILES_DIR не задан (окружение или .env)}"

GDAL_IMAGE=${GDAL_IMAGE:-ghcr.io/osgeo/gdal:ubuntu-small-3.11.3}
PMTILES_IMAGE=${PMTILES_IMAGE:-alpinequest-saas-api}   # в api-образе есть pmtiles
src_name=NE1_HR_LC_SR_W_DR
data="$here/data"
work="$data/overview"
mkdir -p "$data/sources" "$work" "$TILES_DIR/$ver"

zip="$data/sources/$src_name.zip"
if [[ ! -f "$zip" ]]; then
  curl -fL -o "$zip.part" "https://naciscdn.org/naturalearth/10m/raster/$src_name.zip"
  mv "$zip.part" "$zip"
fi

uid="$(id -u):$(id -g)"
gdal() { docker run --rm -u "$uid" -v "$data:/data" "$GDAL_IMAGE" "$@"; }

# z5 = 32×256 = 8192 px на мир. Широты обрезаются до ±85.0511° (предел Меркатора).
rm -f "$work/world-3857.tif" "$work/overview.mbtiles"
gdal gdalwarp -q -t_srs EPSG:3857 -r lanczos \
  -te -20037508.343 -20037508.343 20037508.343 20037508.343 -ts 8192 8192 \
  -co TILED=YES -co COMPRESS=DEFLATE \
  "/vsizip//data/sources/$src_name.zip/$src_name.tif" /data/overview/world-3857.tif
gdal gdal_translate -q -of MBTILES -co TILE_FORMAT=WEBP -co QUALITY=75 \
  -co NAME="Natural Earth" -co DESCRIPTION="Обзор мира z0-5, Natural Earth I" \
  /data/overview/world-3857.tif /data/overview/overview.mbtiles
# Пирамида z0–4 из z5.
gdal gdaladdo -q -r average /data/overview/overview.mbtiles 2 4 8 16 32

out="$TILES_DIR/$ver/overview.pmtiles"
docker run --rm -u "$uid" -v "$work:/w" -v "$TILES_DIR/$ver:/out" --entrypoint pmtiles \
  "$PMTILES_IMAGE" convert /w/overview.mbtiles /out/overview.pmtiles.part
mv "$out.part" "$out"
docker run --rm -v "$TILES_DIR/$ver:/out:ro" --entrypoint pmtiles "$PMTILES_IMAGE" \
  show /out/overview.pmtiles
