# Развёртывание на тестовом сервере (стенд)

Как перенести сервер карт SabyrMap с машины разработчика на тестовый сервер
в локальной сети. На стенде работают API, база, worker офлайн-регионов, Martin
и nginx, там же лежит хранилище карт. Телефоны ходят на стенд по локальной
сети (Wi-Fi). VPN «Континент» появится позже, см. `docs/release-vpn.md`.

## 1. Что нужно от стенда

| Что | Минимум | Почему |
|---|---|---|
| ОС | Linux x86_64 (Ubuntu 22.04/24.04, Debian 12) | образы собраны под amd64 |
| Docker | Docker Engine 24+ с плагином `docker compose` | весь сервер в compose |
| CPU / RAM | 4 ядра, 8–16 ГБ | план §9; Planetiler для Казахстана хочет 8 ГБ heap |
| Диск под карты (`/srv/tiles`) | **≥ 400 ГБ**, лучше NVMe 500 ГБ+ | v1 (Украина) = 115 ГБ; спутник Казахстана ≈ 75–95 ГБ; на время смены версии на диске лежат обе |
| Диск под Docker (`/var/lib/docker`) | ≥ 70 ГБ | кеш тайлов nginx до 50 ГБ живёт внутри контейнера, плюс образы |
| Регионы (`/srv/regions`) | 20–50 ГБ | готовые офлайн-регионы, живут 24 ч |
| Бэкапы (`/srv/backups`) | 5 ГБ, лучше на другом диске | дампы PostGIS за 14 дней |
| ФС для `/srv/tiles` | btrfs или xfs (желательно) | reflink: копия 113 ГБ за секунду при `build.sh --steps satellite` |
| Сеть | статический IP в локальной сети, **без выхода в интернет снаружи** | доступ ограничивает сеть, входа в приложении нет |
| Интернет **со** стенда | на время установки | `docker pull`, сборка образов (pip, GitHub) |

Если у стенда нет интернета вообще, образы привозятся файлами (шаг 4, вариант Б).

## 2. Что передать на стенд

| # | Что | Откуда | Размер | Как |
|---|---|---|---|---|
| 1 | Код (репозиторий) | этот репозиторий, ветка `main` | ~100 МБ | `git push` в GitHub + `git clone` на стенде **или** `git bundle` (шаг 3). Незакоммиченные правки разработчика не переносятся |
| 2 | Карты, версия `v1` | **уже лежат в хранилище стенда** | 115 ГБ | проверить раскладку (шаг 5); копировать заново не нужно |
| 3 | Стили под адрес стенда | готовятся под IP/имя стенда (шаг 6) | < 1 МБ | вместе с картами |
| 4 | Docker-образы | (только без интернета на стенде) | ~3 ГБ | `docker save` / `docker load` |
| 5 | Сертификат стенда `server.crt` | создаётся **на стенде** (шаг 7) | 1 КБ | обратно к разработчику: встраивается в APK (шаг 10) |
| 6 | APK под адрес стенда | собирается у разработчика (шаг 10) | ~60 МБ | на телефоны |

**Не переносить:**
- `.env` разработчика. На стенде создаётся свой, с новыми паролями (шаг 7).
- Базу данных. На стенде она создаётся пустой, а каталог карт заполняет `seed_maps`. В dev-базе только тестовые данные, около 19 МБ; если они всё же нужны, их можно перенести через `pg_dump`.
- `docker-compose.override.yml`. Это файл разработки, он приходит вместе с git, и на стенде его нужно отключить (шаг 7, `COMPOSE_FILE`).
- Google-спутник (`satellite-ukraine-z13.*`). Его нельзя распространять.

## 3. Код

У разработчика:

```sh
git status                 # всё нужное закоммичено
git push origin main       # вариант А: через GitHub
git bundle create sabyrmap.bundle main     # вариант Б: файлом
```

На стенде:

```sh
sudo mkdir -p /opt/sabyrmap && sudo chown "$USER" /opt/sabyrmap
git clone https://github.com/sabyrkalys/SabyrMap.git /opt/sabyrmap       # А
git clone sabyrmap.bundle /opt/sabyrmap                                  # Б
```

## 4. Docker-образы

**А. У стенда есть интернет:** `docker compose build` и `docker compose pull`
на шаге 8 скачают всё сами.

**Б. Интернета нет:** у разработчика

```sh
docker compose -f docker-compose.yml build api
docker save -o sabyrmap-images.tar alpinequest-saas-api postgis/postgis:15-3.4 \
  ghcr.io/maplibre/martin:v0.17.0 nginx:1.27-alpine
```

На стенде выполнить `docker load -i sabyrmap-images.tar`. Имя образа api
зависит от папки проекта (`<папка>-api`), поэтому после загрузки его нужно
переименовать: `docker tag alpinequest-saas-api sabyrmap-api`, если проект лежит в
`/opt/sabyrmap`.

## 5. Карты

Карты уже лежат в хранилище стенда, копировать их не нужно. Нужно только,
чтобы раскладка совпадала с тем, что ждут Martin и API:

```
<TILES_DIR>/v1/satellite.pmtiles     120979934039 байт
<TILES_DIR>/v1/osm.pmtiles             1221223446 байт
<TILES_DIR>/v1/overview.pmtiles           4302696 байт
<TILES_DIR>/v1/{styles,fonts,sprites}/                 (стили — шаг 6)
```

`TILES_DIR` в `.env` — папка хранилища, в которой лежит `v1/` (на шаге 7).
Если файлы называются или лежат иначе, их нужно переложить (`mv` или
жёсткая ссылка внутри того же диска, без копирования) или поправить пути в
`infra/martin/martin.yaml`. Размеры сверить `ls -l`, целостность проверить
через `pmtiles verify` на шаге 9.

Остальные папки создать рядом:

```sh
sudo mkdir -p /srv/regions /srv/backups/postgres
sudo chown -R "$USER" /srv/regions /srv/backups
```

Если хранилище стенда — сетевой диск (NFS/SMB), лучше смонтировать его
только на чтение для `TILES_DIR`. Martin читает архивы произвольным доступом,
и на медленном сетевом диске тайлы будут грузиться заметно дольше.

## 6. Стили под адрес стенда

Стили в `v1` собраны под адрес разработки `http://localhost:3000`. На стенде
с ними карта будет пустой. Их нужно перепубликовать под адрес стенда:

```sh
# на стенде (нужен интернет для сборки образа сборки) …
cd /opt/sabyrmap && TILES_DIR=/srv/tiles tools/build/build.sh v1 --steps styles --tiles-base https://<IP-стенда>/tiles
```

Если на стенде нет интернета, стили собирают у разработчика в отдельную
папку и копируют вместе с картами:

```sh
TILES_DIR=/tmp/stand-tiles tools/build/build.sh v1 --steps styles --tiles-base https://<IP-стенда>/tiles
rsync -a /tmp/stand-tiles/v1/{styles,fonts,sprites} <user>@<стенд>:/srv/tiles/v1/
```

`<IP-стенда>` должен совпадать с `PUBLIC_HOST` на шаге 7.

## 7. `.env` и сертификат

```sh
cd /opt/sabyrmap
cp .env.example .env
openssl rand -hex 24      # → POSTGRES_PASSWORD (и в DATABASE_URL)
openssl rand -hex 32      # → JWT_SECRET_KEY
```

Что поменять в `.env`:

```ini
# На стенде — только боевой compose, без docker-compose.override.yml.
COMPOSE_FILE=docker-compose.yml

POSTGRES_PASSWORD=<сгенерированный>
DATABASE_URL=postgresql://alpinequest:<тот же>@db:5432/alpinequest
JWT_SECRET_KEY=<сгенерированный>
AUTH_DISABLED=true

TILES_DIR=/srv/tiles
REGIONS_DIR=/srv/regions

NGINX_BIND_IP=<IP-стенда>
PUBLIC_HOST=<IP-стенда>                 # или имя, если в сети есть DNS
ALLOWED_CIDRS=127.0.0.1/32,<подсеть Wi-Fi телефонов, напр. 192.168.1.0/24>
```

`ALLOWED_CIDRS`: только подсети, из которых реально ходят телефоны и
разработчики. Подсети docker (`172.16.0.0/12`) и `10.0.0.0/8` целиком
добавлять не нужно.

Сертификат (самоподписанный, на 825 дней):

```sh
CN=<IP-стенда> infra/tls/make-dev-cert.sh
```

Когда `CN` — это IP, скрипт записывает его в сертификат как IP-адрес, иначе
Android не примет сертификат.

## 8. Запуск

```sh
cd /opt/sabyrmap
docker compose build          # (вариант А) образ api
docker compose up -d
docker compose exec api alembic upgrade head                       # схема БД
docker compose exec api python -m app.seed_maps --version v1 --region "Украина"
docker compose restart nginx  # nginx запоминает IP api при старте
```

Бэкап раз в сутки, через cron хоста (`crontab -e`):

```
0 3 * * *  /opt/sabyrmap/infra/backup/pg_backup.sh >> /srv/backups/pg_backup.log 2>&1
```

## 9. Проверка стенда

```sh
# изнутри nginx (адрес 127.0.0.1, проходит allow-list)
docker compose exec nginx wget -qO- --no-check-certificate https://127.0.0.1/api/health      # {"status":"ok"}
# с ноутбука в той же сети
curl -sk https://<IP-стенда>/api/maps | head -c 300                     # каталог, адреса https://<IP-стенда>/tiles/...
curl -sk -o /dev/null -w '%{http_code} %{content_type}\n' https://<IP-стенда>/tiles/satellite/10/600/350
curl -sk -o /dev/null -w '%{http_code} %{content_type}\n' https://<IP-стенда>/tiles/osm/10/600/350   # 200 application/x-protobuf
# целостность архивов
for f in satellite osm overview; do docker compose exec api pmtiles verify /srv/tiles/v1/$f.pmtiles; done
nmap -p 80,443,3000,5432,5433,8000,8500 <IP-стенда>                     # открыты только 80, 443
```

`satellite` пока отдаётся как `image/jpeg`: в v1 известный неверный тип в заголовке,
клиент это переносит.

## 10. Телефоны

Сертификат стенда встраивается в приложение, ставить его на каждый телефон
не нужно:

```sh
scp <user>@<стенд>:/opt/sabyrmap/infra/tls/server.crt app/certs/stand.crt
cd app
mise exec java@temurin-21 -- flutter build apk --debug \
  --dart-define=API_BASE_URL=https://<IP-стенда>/api \
  --dart-define=MAP_SERVER_URL=https://<IP-стенда>/tiles
```

Приложение будет доверять этому сертификату и в запросах к API, и в
MapLibre (`app/certs/README.md`). Если сертификат на стенде перевыпустили,
APK нужно пересобрать.

## 11. Открытые вопросы (уточнить до переезда)

1. IP (или имя) стенда и подсеть Wi-Fi, из которой ходят телефоны.
2. ОС стенда и есть ли на нём интернет.
3. SSH: адрес, пользователь, есть ли sudo и docker.
4. Путь к картам в хранилище стенда и как они там разложены (шаг 5).
5. Нужна ли на стенде копия dev-базы с тестовыми метками и треками или
   стенд начинает с пустой базы.
