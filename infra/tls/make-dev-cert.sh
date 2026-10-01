#!/bin/sh
# Самоподписанный TLS-сертификат для разработки.
# В релизе заменяется сертификатом внутреннего УЦ (пути задаются через TLS_CERT/TLS_KEY).
#
# Использование:  CN=maps.dev.local ./make-dev-cert.sh
#                 CN=192.168.1.10 ./make-dev-cert.sh      # стенд по IP
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
CN=${CN:-${PUBLIC_HOST:-maps.dev.local}}

if [ -f "$DIR/server.crt" ] && [ -f "$DIR/server.key" ]; then
    echo "Сертификат уже существует в $DIR (server.crt/server.key). Удалите его вручную для перевыпуска."
    exit 0
fi

# Стенд без DNS открывают по IP: тогда адрес должен попасть в SAN как IP,
# а не как DNS-имя, иначе Android сертификат не примет.
case $CN in
    *[!0-9.]*) SAN="DNS:$CN" ;;
    *) SAN="IP:$CN" ;;
esac

openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$DIR/server.key" \
    -out "$DIR/server.crt" \
    -subj "/CN=$CN" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "subjectAltName=$SAN,DNS:localhost,IP:127.0.0.1"

chmod 600 "$DIR/server.key"
echo "Готово: $DIR/server.crt, $DIR/server.key (CN=$CN)"
