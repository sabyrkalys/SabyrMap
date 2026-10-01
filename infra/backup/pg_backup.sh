#!/bin/sh
# Ежедневный бэкап PostGIS. Ставится в cron хоста, например:
#   0 3 * * *  /path/to/infra/backup/pg_backup.sh >> /var/log/pg_backup.log 2>&1
# Хранит дампы 14 дней.
set -eu

# Каталог для дампов (лучше отдельный диск). Переопределяется через BACKUP_DIR.
BACKUP_DIR=${BACKUP_DIR:-/srv/backups/postgres}
KEEP_DAYS=${KEEP_DAYS:-14}
DB_SERVICE=${DB_SERVICE:-db}

# Читаем имя пользователя/БД из .env рядом с docker-compose.yml.
PROJECT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
if [ -f "$PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$PROJECT_DIR/.env"
fi
PGUSER=${POSTGRES_USER:-postgres}
PGDB=${POSTGRES_DB:-postgres}

mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/${PGDB}-${STAMP}.sql.gz"

echo "[$(date -Is)] dump $PGDB -> $OUT"
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T "$DB_SERVICE" \
    pg_dump -U "$PGUSER" "$PGDB" | gzip > "$OUT"

# Ротация: удаляем дампы старше KEEP_DAYS дней.
find "$BACKUP_DIR" -name "${PGDB}-*.sql.gz" -type f -mtime "+$KEEP_DAYS" -delete

echo "[$(date -Is)] готово. Текущие дампы:"
ls -1 "$BACKUP_DIR"
