#!/usr/bin/env bash
# Публикует стили, шрифты и спрайты в папку версии карт (план, фаза 2.4–2.5).
#
#   tools/build/publish_styles.sh <версия> <TILES_BASE>
#   tools/build/publish_styles.sh v1 http://localhost:3000          # дев (телефон через adb reverse)
#   tools/build/publish_styles.sh v1 https://maps.example/tiles     # прод, через nginx
#
# Папка назначения: $TILES_DIR/<версия>/{styles,fonts,sprites}; TILES_DIR берётся
# из окружения или из корневого .env. После публикации: docker compose restart martin.
set -euo pipefail

ver=${1:?версия, напр. v1}
base=${2:?адрес тайлов снаружи, напр. https://maps.example/tiles}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

if [[ -z "${TILES_DIR:-}" && -f "$root/.env" ]]; then
  TILES_DIR=$(grep -E '^TILES_DIR=' "$root/.env" | tail -1 | cut -d= -f2-)
fi
: "${TILES_DIR:?TILES_DIR не задан (окружение или .env)}"
dest="$TILES_DIR/$ver"
mkdir -p "$dest/styles" "$dest/fonts" "$dest/sprites"

python3 "$here/styles/build_styles.py" --tiles-base "$base" --out "$dest/styles"

# Noto Sans: кириллица + латиница. Martin сам режет их в глифы PBF.
fonts_src=${FONTS_SRC:-/usr/share/fonts/noto}
for f in NotoSans-Regular.ttf NotoSans-Bold.ttf NotoSans-Italic.ttf; do
  install -m 644 "$fonts_src/$f" "$dest/fonts/$f"
done

rm -rf "$dest/sprites/sabyr"
cp -r "$here/sprites/sabyr" "$dest/sprites/sabyr"

echo "Опубликовано в $dest"
