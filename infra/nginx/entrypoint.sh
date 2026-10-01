#!/bin/sh
# Точка входа nginx:
#  1) из ALLOWED_CIDRS (список через запятую) собирает allow/deny;
#  2) подставляет переменные окружения в шаблон конфигурации;
#  3) запускает nginx.
set -eu

ALLOW_FILE=/etc/nginx/allowed_cidrs.conf
: > "$ALLOW_FILE"

OLD_IFS=$IFS
IFS=,
for cidr in ${ALLOWED_CIDRS:-}; do
    # обрезаем пробелы вокруг элемента
    cidr=$(printf '%s' "$cidr" | tr -d '[:space:]')
    [ -n "$cidr" ] && echo "allow $cidr;" >> "$ALLOW_FILE"
done
IFS=$OLD_IFS
echo "deny all;" >> "$ALLOW_FILE"

# Кеш тайлов должен существовать.
mkdir -p /var/cache/nginx/tiles

# Подставляем только наши переменные, не трогая переменные nginx ($host и т.п.).
envsubst '${PUBLIC_HOST} ${TLS_CERT} ${TLS_KEY}' \
    < /etc/nginx/templates/nginx.conf.template \
    > /etc/nginx/conf.d/default.conf

nginx -t
exec nginx -g 'daemon off;'
