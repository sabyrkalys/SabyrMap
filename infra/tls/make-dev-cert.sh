#!/bin/sh
# Самоподписанный TLS-сертификат для разработки.
# В релизе заменяется сертификатом внутреннего УЦ (пути задаются через TLS_CERT/TLS_KEY).
#
# Использование:  CN=maps.dev.local ./make-dev-cert.sh
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
CN=${CN:-${PUBLIC_HOST:-maps.dev.local}}

if [ -f "$DIR/server.crt" ] && [ -f "$DIR/server.key" ]; then
    echo "Сертификат уже существует в $DIR (server.crt/server.key). Удалите его вручную для перевыпуска."
    exit 0
fi

openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$DIR/server.key" \
    -out "$DIR/server.crt" \
    -subj "/CN=$CN" \
    -addext "subjectAltName=DNS:$CN,DNS:localhost,IP:127.0.0.1"

chmod 600 "$DIR/server.key"
echo "Готово: $DIR/server.crt, $DIR/server.key (CN=$CN)"
