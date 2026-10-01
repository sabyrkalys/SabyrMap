FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libpq-dev curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Бинарник pmtiles (go-pmtiles) — нужен worker'у для нарезки регионов (фаза 3).
ARG PMTILES_VERSION=1.31.2
RUN curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
        -o /tmp/pmtiles.tar.gz \
    && tar -xzf /tmp/pmtiles.tar.gz -C /usr/local/bin pmtiles \
    && rm /tmp/pmtiles.tar.gz \
    && pmtiles version

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
