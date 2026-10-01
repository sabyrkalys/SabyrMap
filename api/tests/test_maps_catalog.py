import json
from pathlib import Path

from tests.map_helpers import map_server, seeded  # noqa: F401

FIXTURE = Path(__file__).parent / "fixtures" / "client_catalog_example.json"
# Fields the app's MapSource.fromJson reads, taken from its own catalog.
CLIENT_EXAMPLE = json.loads(FIXTURE.read_text(encoding="utf-8"))
CLIENT_SOURCE_KEYS = set().union(*(s.keys() for p in CLIENT_EXAMPLE["providers"] for s in p["sources"])) | {
    "tileUrlTemplate", "styleUrl", "extraParams", "thumbnailAsset",
}
# Ours on top; the app ignores keys it does not know.
SERVER_EXTRA_KEYS = {"downloadable", "version"}


def test_catalog_is_public_and_lists_server_maps(client, seeded):
    response = client.get("/maps")

    assert response.status_code == 200
    providers = response.json()["providers"]
    assert [p["id"] for p in providers] == ["server"]
    assert providers[0]["name"] == "Сервер карт"
    ids = [s["id"] for s in providers[0]["sources"]]
    assert ids == ["server-hybrid-day", "server-hybrid-night", "server-vector-day", "server-vector-night",
                   "server-satellite"]


def test_catalog_matches_the_client_format(client, seeded):
    body = client.get("/maps").json()

    assert set(body) == set(CLIENT_EXAMPLE) - {"version"} | {"providers"}
    for provider in body["providers"]:
        assert {"id", "name", "sources"} <= provider.keys()
        assert isinstance(provider["isolated"], bool)
        for source in provider["sources"]:
            assert set(source) <= CLIENT_SOURCE_KEYS | SERVER_EXTRA_KEYS
            assert {"id", "name", "format", "storageMode"} <= source.keys()
            assert source["format"] in ("vector", "raster")
            assert source["storageMode"] in ("onlineOnly", "onlineCache", "offlineRegion")
            assert ("styleUrl" in source) != ("tileUrlTemplate" in source)
            assert isinstance(source["minZoom"], int) and isinstance(source["maxZoom"], int)


def test_catalog_builds_absolute_urls_from_the_public_tiles_url(client, seeded):
    sources = {s["id"]: s for s in client.get("/maps").json()["providers"][0]["sources"]}

    assert sources["server-hybrid-day"]["styleUrl"] == "https://maps.test/tiles/style/hybrid-day"
    assert sources["server-satellite"]["tileUrlTemplate"] == "https://maps.test/tiles/satellite/{z}/{x}/{y}"
    assert sources["server-satellite"]["canBeOverlay"] is True
    assert sources["server-hybrid-day"]["storageMode"] == "onlineCache"
    assert sources["server-hybrid-day"]["version"] == "v1"


def test_public_tiles_url_defaults_to_public_host(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "TILES_PUBLIC_URL", None)
    monkeypatch.setattr(settings, "PUBLIC_HOST", "maps.example")
    assert settings.tiles_public_url == "https://maps.example/tiles"


def test_seed_names_maps_after_the_region_and_is_idempotent(seeded):
    from app.models.map_catalog import MapCatalogEntry
    from app.seed_maps import seed

    seed(seeded, version="v1", region="Казахстан")

    entries = seeded.query(MapCatalogEntry).all()
    assert len(entries) == 5
    hybrid = seeded.get(MapCatalogEntry, "server-hybrid-day")
    assert hybrid.name == "Казахстан · спутник + дороги"
    assert hybrid.version == "v1"
