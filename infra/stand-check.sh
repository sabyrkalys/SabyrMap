#!/usr/bin/env bash
# Проверка стенда перед запуском: .env заполнен, Docker есть, IP наш, карты на
# месте, папки и сертификат готовы. Ничего не меняет.
#
#   infra/stand-check.sh            # из папки проекта, после cp stand.env .env
#
# ✔ — в порядке, ! — предупреждение, ✘ — ошибка (запускать рано).
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
env_file="$root/.env"
errors=0
ok()   { echo "  ✔ $*"; }
warn() { echo "  ! $*"; }
fail() { echo "  ✘ $*"; errors=$((errors + 1)); }
get()  { grep -E "^$1=" "$env_file" | tail -1 | cut -d= -f2-; }

echo "Файл .env"
if [[ ! -f "$env_file" ]]; then
  fail "нет $env_file — скопируйте: cp stand.env .env"
  exit 1
fi
left=$(grep -E '^[A-Z_]+=.*<[^>]+>' "$env_file" | cut -d= -f1)
if [[ -n "$left" ]]; then fail "не заполнено: $(echo $left | tr '\n' ' ')"; else ok "все значения заполнены"; fi
[[ "$(get COMPOSE_FILE)" == "docker-compose.yml" ]] && ok "COMPOSE_FILE=docker-compose.yml" \
  || fail "COMPOSE_FILE должен быть docker-compose.yml (иначе подхватится файл разработчика)"
for v in POSTGRES_PASSWORD JWT_SECRET_KEY; do
  val=$(get $v)
  if [[ "$val" == change-me* || ${#val} -lt 24 ]]; then fail "$v: слишком короткий или учебный — openssl rand -hex 32"; fi
done

echo "Docker"
if command -v docker >/dev/null; then
  ok "$(docker --version)"
  if docker compose version >/dev/null 2>&1; then ok "$(docker compose version)"; else fail "нет docker compose (нужен Compose v2)"; fi
  docker info >/dev/null 2>&1 && ok "Docker доступен пользователю $(id -un)" \
    || fail "нет доступа к Docker: добавить $(id -un) в группу docker или запускать через sudo"
else
  fail "Docker не установлен"
fi

echo "Сеть"
bind_ip=$(get NGINX_BIND_IP)
if [[ -n "$bind_ip" ]] && ip -o addr 2>/dev/null | grep -qw "inet $bind_ip"; then
  ok "NGINX_BIND_IP=$bind_ip есть на этом сервере"
else
  fail "NGINX_BIND_IP=$bind_ip не найден среди адресов сервера (ip -o addr)"
fi
cidrs=$(get ALLOWED_CIDRS)
case ",$cidrs," in
  *,0.0.0.0/0,*) fail "ALLOWED_CIDRS открывает доступ всем (0.0.0.0/0)" ;;
  *,10.0.0.0/8,*|*,172.16.0.0/12,*) warn "ALLOWED_CIDRS: целый частный диапазон — лучше только подсеть Wi-Fi" ;;
  *) ok "ALLOWED_CIDRS=$cidrs" ;;
esac
for port in 80 443; do
  if ss -ltnH "sport = :$port" 2>/dev/null | grep -q .; then
    docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q ":$port->" \
      && ok "порт $port занят контейнером (уже запущено?)" || fail "порт $port занят другой программой"
  else
    ok "порт $port свободен"
  fi
done

echo "Карты"
tiles=$(get TILES_DIR)
declare -A expected=([satellite]=120979934039 [osm]=1221223446 [overview]=4302696)
if [[ ! -d "$tiles/v1" ]]; then
  fail "нет папки $tiles/v1 (TILES_DIR=$tiles)"
else
  for name in satellite osm overview; do
    f="$tiles/v1/$name.pmtiles"
    if [[ ! -f "$f" ]]; then fail "нет $f"; continue; fi
    size=$(stat -c %s "$f")
    if [[ "$size" == "${expected[$name]}" ]]; then ok "$name.pmtiles ($size байт)"
    else warn "$name.pmtiles: $size байт, ожидалось ${expected[$name]} — другая сборка или файл не докопирован"; fi
    head -c 7 "$f" | grep -q PMTiles || fail "$name.pmtiles: не PMTiles"
  done
  [[ -w "$tiles/v1" ]] && ok "в $tiles/v1 можно записать стили" \
    || warn "нет права записи в $tiles/v1 — стили опубликует пользователь с правами (шаг 6)"
  [[ -d "$tiles/v1/styles" ]] && ok "стили опубликованы" || warn "стилей ещё нет — шаг 6 docs/deploy-stand.md"
fi
regions=$(get REGIONS_DIR)
if [[ -d "$regions" && -w "$regions" ]]; then ok "REGIONS_DIR=$regions"
else fail "REGIONS_DIR=$regions: нет папки или права записи (sudo mkdir -p $regions && sudo chown $(id -un) $regions)"; fi
avail=$(df -BG --output=avail "${regions%/*}" 2>/dev/null | tail -1 | tr -dc 0-9)
[[ -n "$avail" && "$avail" -lt 20 ]] && warn "под регионы свободно ${avail} ГБ (желательно 20–50)"

echo "Сертификат"
crt="$root/infra/tls/server.crt"
host=$(get PUBLIC_HOST)
if [[ ! -f "$crt" || ! -f "$root/infra/tls/server.key" ]]; then
  fail "нет сертификата — CN=$host infra/tls/make-dev-cert.sh"
elif openssl x509 -in "$crt" -noout -checkhost "$host" 2>/dev/null | grep -q "does match" \
  || openssl x509 -in "$crt" -noout -checkip "$host" 2>/dev/null | grep -q "does match"; then
  ok "сертификат выписан на $host, действует до $(openssl x509 -in "$crt" -noout -enddate | cut -d= -f2)"
else
  fail "сертификат не для $host — удалить infra/tls/server.{crt,key} и выпустить заново: CN=$host infra/tls/make-dev-cert.sh"
fi

echo
if (( errors )); then echo "Ошибок: $errors. Исправьте и запустите проверку снова."; exit 1; fi
echo "Готово к запуску: docs/deploy-stand.md, шаг 8."
