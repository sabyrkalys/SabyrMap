#!/usr/bin/env bash
# Публикует стили карт под адрес стенда (PUBLIC_HOST из .env). Интернет не
# нужен: генератор (tools/build/styles/build_styles.py) запускается в образе
# api, шрифты берутся из комплекта поставки, значки — из репозитория.
#
#   infra/stand-styles.sh <папка-со-шрифтами> [версия]
#   infra/stand-styles.sh ../fonts                       # → $TILES_DIR/v1/{styles,fonts,sprites}
#
# После публикации: docker compose restart martin
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fonts_src=${1:?папка со шрифтами NotoSans-*.ttf, напр. ../fonts}
ver=${2:-v1}
get() { grep -E "^$1=" "$root/.env" | tail -1 | cut -d= -f2-; }
tiles=$(get TILES_DIR)
host=$(get PUBLIC_HOST)
project=$(get COMPOSE_PROJECT_NAME)
: "${tiles:?TILES_DIR не задан в .env}" "${host:?PUBLIC_HOST не задан в .env}"
image=${project:-sabyrmap}-api
dest="$tiles/$ver"

[[ -d "$dest" ]] || { echo "нет папки $dest" >&2; exit 1; }
docker image inspect "$image" >/dev/null 2>&1 || { echo "нет образа $image (docker load / docker compose build)" >&2; exit 1; }
mkdir -p "$dest/styles" "$dest/fonts" "$dest/sprites"

install -m 644 "$fonts_src"/NotoSans-{Regular,Bold,Italic}.ttf "$dest/fonts/"
rm -rf "$dest/sprites/sabyr"
cp -r "$root/tools/build/sprites/sabyr" "$dest/sprites/sabyr"

docker run --rm -u "$(id -u):$(id -g)" --entrypoint python \
  -v "$root/tools/build/styles:/styles:ro" -v "$dest/styles:/out" \
  "$image" /styles/build_styles.py --tiles-base "https://$host/tiles" --out /out

echo "Стили опубликованы в $dest под https://$host/tiles. Дальше: docker compose restart martin"
