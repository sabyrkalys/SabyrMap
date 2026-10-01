# Образ сборки карт (план, фаза 2): всё, что нужно конвейеру tools/build/build.sh.
#   python3 + Pillow (WebP)  — satellite.py: JPEG → WebP, пирамида, тип тайлов
#   GDAL                     — overview.sh: Natural Earth → тайлы z0–5
#   go-pmtiles               — MBTiles → PMTiles, show/verify
#   Java 21 + planetiler.jar — вектор OpenMapTiles из OSM
#   Noto Sans                — шрифты для publish_styles.sh
#
# Собирается и запускается из build.sh; руками:
#   docker build -t sabyrmap-build tools/build
FROM eclipse-temurin:21-jre-noble

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pil gdal-bin fonts-noto-core curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG PMTILES_VERSION=1.31.2
RUN curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
        -o /tmp/pmtiles.tar.gz \
    && tar -xzf /tmp/pmtiles.tar.gz -C /usr/local/bin pmtiles \
    && rm /tmp/pmtiles.tar.gz \
    && pmtiles version

ARG PLANETILER_VERSION=0.10.2
RUN mkdir -p /opt/planetiler \
    && curl -fsSL "https://github.com/onthegomap/planetiler/releases/download/v${PLANETILER_VERSION}/planetiler.jar" \
        -o /opt/planetiler/planetiler.jar

ENV FONTS_SRC=/usr/share/fonts/truetype/noto \
    PLANETILER_JAR=/opt/planetiler/planetiler.jar \
    HOME=/tmp
WORKDIR /build
