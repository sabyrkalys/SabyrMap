import uuid
from datetime import datetime, timedelta, timezone

from app.config import settings
from app.models.region_job import RegionJob
from tests.map_helpers import map_server, seeded  # noqa: F401

# ~5×5 km around Almaty's Big Almaty Lake, inside every fake archive.
BBOX = [76.95, 43.03, 77.01, 43.07]


def _register(client, email):
    response = client.post("/auth/register", json={"email": email, "password": "s3cret-pass"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _create(client, headers, **overrides):
    body = {"map_id": "server-hybrid-day", "bbox": BBOX, "max_zoom": 15, **overrides}
    return client.post("/regions", json=body, headers=headers)


def _make_ready(db, job_id, files=None):
    job = db.get(RegionJob, uuid.UUID(job_id))
    now = datetime.now(timezone.utc)
    job.status = "ready"
    job.progress = 1.0
    job.files = files or [{"name": "satellite.mbtiles", "size": 10, "sha256": "ab" * 32}]
    job.size_bytes = 10
    job.ready_at = now
    job.expires_at = now + timedelta(hours=24)
    db.flush()
    return job


def test_regions_need_login(client, seeded):
    assert client.post("/regions/estimate", json={"map_id": "x", "bbox": BBOX, "max_zoom": 1}).status_code == 401
    assert client.get("/regions").status_code == 401


def test_estimate_splits_by_archive(client, seeded):
    headers = _register(client, "est@example.test")

    response = client.post("/regions/estimate", json={"map_id": "server-hybrid-day", "bbox": BBOX, "max_zoom": 15},
                           headers=headers)

    assert response.status_code == 200
    body = response.json()
    parts = {p["tileset"]: p for p in body["parts"]}
    assert set(parts) == {"overview", "osm", "satellite"}
    # overview stops at its own max zoom (5): one tile per zoom for a small area.
    assert parts["overview"]["tiles"] == 6
    assert parts["satellite"]["tiles"] > parts["osm"]["tiles"]  # z15 vs z14
    assert body["style_bytes"] > 0
    assert body["total_bytes"] == sum(p["bytes"] for p in body["parts"]) + body["style_bytes"]
    assert body["allowed"] is True
    assert body["max_bytes"] == settings.REGION_MAX_BYTES


def test_estimate_of_a_raster_map_has_no_style(client, seeded):
    headers = _register(client, "est-raster@example.test")
    body = client.post("/regions/estimate", json={"map_id": "server-satellite", "bbox": BBOX, "max_zoom": 12},
                       headers=headers).json()
    assert [p["tileset"] for p in body["parts"]] == ["satellite"]
    assert body["style_bytes"] == 0


def test_estimate_outside_the_data_counts_only_the_overview(client, seeded):
    headers = _register(client, "est-out@example.test")
    body = client.post("/regions/estimate", json={"map_id": "server-hybrid-day", "bbox": [10, 50, 10.1, 50.1],
                                                  "max_zoom": 14}, headers=headers).json()
    assert [p["tileset"] for p in body["parts"]] == ["overview"]


def test_create_queues_a_job(client, seeded):
    headers = _register(client, "create@example.test")

    response = _create(client, headers, name="Большое Алматинское")

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "queued"
    assert body["bbox"] == BBOX
    assert body["version"] == "v1"
    assert body["name"] == "Большое Алматинское"
    assert body["files"] == []


def test_create_rejects_bad_input(client, seeded):
    headers = _register(client, "bad@example.test")
    assert _create(client, headers, map_id="nope").status_code == 404
    assert _create(client, headers, max_zoom=settings.REGION_MAX_ZOOM + 1).status_code == 422
    assert _create(client, headers, bbox=[77, 43, 76, 44]).status_code == 422
    assert _create(client, headers, bbox=[1, 2, 3]).status_code == 422


def test_create_rejects_regions_over_the_size_limit(client, seeded, monkeypatch):
    monkeypatch.setattr(settings, "REGION_MAX_BYTES", 1000)
    headers = _register(client, "big@example.test")

    response = _create(client, headers)

    assert response.status_code == 413
    estimate = client.post("/regions/estimate", json={"map_id": "server-hybrid-day", "bbox": BBOX, "max_zoom": 15},
                           headers=headers).json()
    assert estimate["allowed"] is False


def test_create_is_rate_limited_per_user(client, seeded, monkeypatch):
    monkeypatch.setattr(settings, "REGION_MAX_PER_HOUR", 2)
    headers = _register(client, "rate@example.test")
    other = _register(client, "rate-other@example.test")

    assert _create(client, headers, max_zoom=10).status_code == 201
    assert _create(client, headers, max_zoom=11).status_code == 201
    assert _create(client, headers, max_zoom=12).status_code == 429
    assert _create(client, other, max_zoom=12).status_code == 201


def test_same_request_returns_the_pending_job(client, seeded):
    headers = _register(client, "again@example.test")
    first = _create(client, headers).json()

    second = _create(client, headers)

    assert second.status_code == 200
    assert second.json()["id"] == first["id"]


def test_ready_region_of_another_user_is_reused_without_cutting(client, seeded):
    alice = _register(client, "alice@example.test")
    bob = _register(client, "bob@example.test")
    alice_job = _make_ready(seeded, _create(client, alice).json()["id"])

    response = _create(client, bob)

    assert response.status_code == 201
    body = response.json()
    assert body["id"] != str(alice_job.id)
    assert body["status"] == "ready"
    assert body["files"] == alice_job.files
    bob_job = seeded.get(RegionJob, uuid.UUID(body["id"]))
    assert bob_job.storage_dir == alice_job.storage_dir


def test_expired_region_is_not_reused(client, seeded):
    alice = _register(client, "alice-exp@example.test")
    bob = _register(client, "bob-exp@example.test")
    job = _make_ready(seeded, _create(client, alice).json()["id"])
    job.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    seeded.flush()

    body = _create(client, bob).json()

    assert body["status"] == "queued"


def test_get_and_list_only_own_regions(client, seeded):
    alice = _register(client, "alice-own@example.test")
    bob = _register(client, "bob-own@example.test")
    job_id = _create(client, alice).json()["id"]

    assert client.get(f"/regions/{job_id}", headers=alice).status_code == 200
    assert client.get(f"/regions/{job_id}", headers=bob).status_code == 404
    assert [j["id"] for j in client.get("/regions", headers=alice).json()["items"]] == [job_id]
    assert client.get("/regions", headers=bob).json()["items"] == []


def test_download_hands_the_file_to_nginx(client, seeded):
    headers = _register(client, "dl@example.test")
    job = _make_ready(seeded, _create(client, headers).json()["id"])

    response = client.get(f"/regions/{job.id}/download/satellite.mbtiles", headers=headers)

    assert response.status_code == 200
    assert response.headers["x-accel-redirect"] == f"/regions-files/{job.storage_dir}/satellite.mbtiles"
    assert "satellite.mbtiles" in response.headers["content-disposition"]
    assert response.content == b""


def test_download_checks_owner_status_and_file_name(client, seeded):
    alice = _register(client, "dl-alice@example.test")
    bob = _register(client, "dl-bob@example.test")
    job_id = _create(client, alice).json()["id"]

    assert client.get(f"/regions/{job_id}/download/satellite.mbtiles", headers=alice).status_code == 409
    _make_ready(seeded, job_id)
    assert client.get(f"/regions/{job_id}/download/satellite.mbtiles", headers=bob).status_code == 404
    assert client.get(f"/regions/{job_id}/download/other.mbtiles", headers=alice).status_code == 404
    assert client.get(f"/regions/{job_id}/download/..%2F..%2Fetc%2Fpasswd", headers=alice).status_code == 404


def test_delete_removes_only_own_region(client, seeded):
    alice = _register(client, "del-alice@example.test")
    bob = _register(client, "del-bob@example.test")
    job_id = _create(client, alice).json()["id"]

    assert client.delete(f"/regions/{job_id}", headers=bob).status_code == 404
    assert client.delete(f"/regions/{job_id}", headers=alice).status_code == 204
    assert client.get(f"/regions/{job_id}", headers=alice).status_code == 404
