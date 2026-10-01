#!/usr/bin/env bash
# Конвейер сборки карт (план, фаза 2): одна версия карт целиком.
#
#   tools/build/build.sh <версия> --satellite <файл> [--area kazakhstan]
#                        [--tiles-base URL] [--steps satellite,osm,overview,styles]
#
#   --satellite   исходник спутника:
#                   .mbtiles (JPEG/PNG/WebP) → WebP + пирамида до z5 → PMTiles;
#                   .pmtiles (уже WebP)      → копия (reflink) + верный тип тайлов.
#   --area        регион OSM для Planetiler (Geofabrik), по умолчанию kazakhstan.
#   --tiles-base  адрес тайлов снаружи, зашивается в стили; по умолчанию
#                 https://PUBLIC_HOST/tiles из .env. В деве: http://localhost:3000.
#   --steps       только эти шаги (по умолчанию все, по порядку).
#
# Результат: $TILES_DIR/<версия>/{satellite,osm,overview}.pmtiles + styles, fonts,
# sprites. TILES_DIR — из окружения или корневого .env. Промежуточные файлы
# (MBTiles WebP ≈ размер итогового спутника, загрузки OSM) — в $BUILD_WORK
# (по умолчанию tools/build/data). Всё считается в образе tools/build/Dockerfile,
# на хосте нужен только docker. Шаг спутника возобновляется после обрыва.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
env_get() { [[ -f "$root/.env" ]] && grep -E "^$1=" "$root/.env" | tail -1 | cut -d= -f2- || true; }

ver=${1:?"использование: build.sh <версия> --satellite <файл> [--area kazakhstan] [--tiles-base URL] [--steps ...]"}
shift
satellite="" area=kazakhstan tiles_base="" steps=satellite,osm,overview,styles
while [[ $# -gt 0 ]]; do
  case $1 in
    --satellite) satellite=$2; shift 2 ;;
    --area) area=$2; shift 2 ;;
    --tiles-base) tiles_base=$2; shift 2 ;;
    --steps) steps=$2; shift 2 ;;
    *) echo "неизвестный параметр: $1" >&2; exit 2 ;;
  esac
done
has_step() { [[ ",$steps," == *",$1,"* ]]; }

TILES_DIR=${TILES_DIR:-$(env_get TILES_DIR)}
: "${TILES_DIR:?TILES_DIR не задан (окружение или .env)}"
BUILD_WORK=${BUILD_WORK:-$here/data}
if [[ -z "$tiles_base" ]]; then
  host=$(env_get PUBLIC_HOST)
  tiles_base=${TILES_PUBLIC_URL:-$(env_get TILES_PUBLIC_URL)}
  tiles_base=${tiles_base:-https://${host:?PUBLIC_HOST не задан, укажите --tiles-base}/tiles}
fi
if has_step satellite; then
  [[ -f "$satellite" ]] || { echo "нужен --satellite <файл .mbtiles|.pmtiles>" >&2; exit 2; }
fi
[[ -n "$satellite" ]] && satellite=$(realpath "$satellite")
mkdir -p "$TILES_DIR/$ver" "$BUILD_WORK"

IMAGE=${BUILD_IMAGE:-sabyrmap-build}
echo "== образ сборки $IMAGE"
docker build -q -t "$IMAGE" "$here" >/dev/null

# /build — скрипты, /build/data — рабочая папка, /tiles — TILES_DIR, /src — исходник спутника.
run() {
  local src_mount=()
  [[ -n "$satellite" ]] && src_mount=(-v "$(dirname "$satellite"):/src:ro")
  docker run --rm -u "$(id -u):$(id -g)" \
    -v "$here:/build" -v "$BUILD_WORK:/build/data" -v "$TILES_DIR:/tiles" "${src_mount[@]}" \
    -e TILES_DIR=/tiles "$IMAGE" "$@"
}
out=/tiles/$ver
started=$(date +%s)

if has_step satellite; then
  name=$(basename "$satellite")
  case $name in
    *.mbtiles)
      echo "== спутник: $name → WebP + пирамида → PMTiles"
      run python3 satellite.py recode "/src/$name" "data/work/$ver/satellite.mbtiles" --min-zoom 5
      run pmtiles convert "data/work/$ver/satellite.mbtiles" "$out/satellite.pmtiles.part"
      ;;
    *.pmtiles)
      echo "== спутник: $name (PMTiles) → копия + тип тайлов"
      # reflink на btrfs/xfs — мгновенно и без места; иначе обычная копия.
      run cp --reflink=auto "/src/$name" "$out/satellite.pmtiles.part"
      ;;
    *) echo "спутник: ожидается .mbtiles или .pmtiles" >&2; exit 2 ;;
  esac
  run python3 satellite.py set-type "$out/satellite.pmtiles.part"
  run mv "$out/satellite.pmtiles.part" "$out/satellite.pmtiles"
fi

if has_step osm; then
  echo "== вектор OSM: Planetiler, область $area"
  run sh -c "java -Xmx${PLANETILER_XMX:-8g} -jar \$PLANETILER_JAR --area=$area --download \
    --output=$out/osm.part.pmtiles --force && mv $out/osm.part.pmtiles $out/osm.pmtiles"
fi

if has_step overview; then
  echo "== обзор мира: Natural Earth"
  run ./overview.sh "$out"
fi

if has_step styles; then
  echo "== стили, шрифты, спрайты (тайлы: $tiles_base)"
  run ./publish_styles.sh "$ver" "$tiles_base"
fi

echo "== проверка"
for f in satellite osm overview; do
  [[ -f "$TILES_DIR/$ver/$f.pmtiles" ]] || { echo "  $f.pmtiles: нет"; continue; }
  run pmtiles verify "$out/$f.pmtiles" >/dev/null 2>&1 && ok=ok || ok="ОШИБКА verify"
  run pmtiles show --header-json "$out/$f.pmtiles" | python3 -c "
import json, sys; h = json.load(sys.stdin)
print(f\"  $f.pmtiles: {h['tile_type']}, z{h['minzoom']}–{h['maxzoom']}, bounds {h['bounds']}, $ok\")"
done

cat <<EOF
Готово за $(( ($(date +%s) - started) / 60 )) мин: $TILES_DIR/$ver
Дальше:
  1. infra/martin/martin.yaml: пути /srv/tiles/<версия>/… → $ver (если версия новая);
     docker compose restart martin
  2. docker compose exec api python -m app.seed_maps --version $ver --region "<Регион>"
EOF
