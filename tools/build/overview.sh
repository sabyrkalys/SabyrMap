#!/usr/bin/env bash
# Обзорная карта мира z0–5 (план, фаза 2.3): Natural Earth I с отмывкой рельефа
# (общественное достояние) → Web Mercator → MBTiles WebP → overview.pmtiles.
#
#   overview.sh <папка-версии>          # → <папка-версии>/overview.pmtiles
#
# Нужны GDAL и pmtiles — запускается в образе сборки через build.sh
# (tools/build/build.sh <версия> --steps overview).
set -euo pipefail

out_dir=${1:?папка версии, напр. /tiles/v1}
here=$(cd "$(dirname "$0")" && pwd)
src_name=NE1_HR_LC_SR_W_DR
data="$here/data"
work="$data/overview"
mkdir -p "$data/sources" "$work" "$out_dir"

zip="$data/sources/$src_name.zip"
if [[ ! -f "$zip" ]]; then
  curl -fL -o "$zip.part" "https://naciscdn.org/naturalearth/10m/raster/$src_name.zip"
  mv "$zip.part" "$zip"
fi

# z5 = 32×256 = 8192 px на мир. Широты обрезаются до ±85.0511° (предел Меркатора).
rm -f "$work/world-3857.tif" "$work/overview.mbtiles"
gdalwarp -q -t_srs EPSG:3857 -r lanczos \
  -te -20037508.343 -20037508.343 20037508.343 20037508.343 -ts 8192 8192 \
  -co TILED=YES -co COMPRESS=DEFLATE \
  "/vsizip/$zip/$src_name.tif" "$work/world-3857.tif"
gdal_translate -q -of MBTILES -co TILE_FORMAT=WEBP -co QUALITY=75 \
  -co NAME="Natural Earth" -co DESCRIPTION="Обзор мира z0-5, Natural Earth I" \
  "$work/world-3857.tif" "$work/overview.mbtiles"
# Пирамида z0–4 из z5. Не gdaladdo: GDAL 3.8 пишет её зумы в PNG, хотя
# архив объявлен WebP (файл выходит в 6 раз больше и форматы смешаны).
python3 "$here/satellite.py" pyramid "$work/overview.mbtiles" --min-zoom 0 --quality 75

pmtiles convert "$work/overview.mbtiles" "$out_dir/overview.pmtiles.part"
mv "$out_dir/overview.pmtiles.part" "$out_dir/overview.pmtiles"
