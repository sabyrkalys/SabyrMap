def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


_LINE_A = {"type": "LineString", "coordinates": [[7.6, 45.9], [7.7, 46.0], [7.8, 46.05]]}
_LINE_B = {"type": "LineString", "coordinates": [[1.0, 1.0], [2.0, 2.0]]}


def test_create_and_get_track(client):
    headers = _register(client, "track-create@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Ridge Loop", "geom": _LINE_A}, headers=headers
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Ridge Loop"
    assert body["geom"] == _LINE_A

    get_response = client.get(f"/tracks/{body['id']}", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["id"] == body["id"]


def test_list_tracks_returns_created(client):
    headers = _register(client, "track-list@example.test")
    client.post("/tracks", json={"name": "A", "geom": _LINE_B}, headers=headers)
    response = client.get("/tracks", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 50
    assert body["offset"] == 0
    assert any(item["name"] == "A" for item in body["items"])


def test_get_track_not_found(client):
    import uuid

    headers = _register(client, "track-404@example.test")
    response = client.get(f"/tracks/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_get_track_forbidden_for_other_org(client):
    owner_headers = _register(client, "track-owner-a@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Secret", "geom": _LINE_A}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-owner-b@example.test")
    response = client.get(f"/tracks/{track_id}", headers=other_headers)
    assert response.status_code == 403


def test_create_track_rejects_wrong_geometry_type(client):
    headers = _register(client, "track-badgeom@example.test")
    response = client.post(
        "/tracks",
        json={"name": "Bad", "geom": {"type": "Point", "coordinates": [1.0, 2.0]}},
        headers=headers,
    )
    assert response.status_code == 422


def test_create_track_rejects_single_point_linestring(client):
    headers = _register(client, "track-shortline@example.test")
    response = client.post(
        "/tracks",
        json={"name": "TooShort", "geom": {"type": "LineString", "coordinates": [[1.0, 2.0]]}},
        headers=headers,
    )
    assert response.status_code == 422


def test_list_tracks_pagination(client):
    headers = _register(client, "track-page@example.test")
    for i in range(3):
        client.post(
            "/tracks",
            json={"name": f"T{i}", "geom": {"type": "LineString", "coordinates": [[float(i), float(i)], [float(i) + 1, float(i) + 1]]}},
            headers=headers,
        )
    response = client.get("/tracks?limit=2&offset=1", headers=headers)
    body = response.json()
    assert len(body["items"]) == 2
    assert body["limit"] == 2
    assert body["offset"] == 1


def test_update_track_name_only(client):
    headers = _register(client, "track-update@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Old", "geom": _LINE_B}, headers=headers
    )
    track_id = create_response.json()["id"]

    response = client.patch(f"/tracks/{track_id}", json={"name": "New"}, headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "New"
    assert body["geom"] == _LINE_B


def test_update_track_forbidden_without_edit_access(client):
    owner_headers = _register(client, "track-edit-owner@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Mine", "geom": _LINE_B}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-edit-other@example.test")
    response = client.patch(f"/tracks/{track_id}", json={"name": "Hacked"}, headers=other_headers)
    assert response.status_code == 403


def test_delete_track_soft_deletes(client):
    headers = _register(client, "track-delete@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Gone", "geom": _LINE_B}, headers=headers
    )
    track_id = create_response.json()["id"]

    delete_response = client.delete(f"/tracks/{track_id}", headers=headers)
    assert delete_response.status_code == 204

    get_response = client.get(f"/tracks/{track_id}", headers=headers)
    assert get_response.status_code == 404

    list_response = client.get("/tracks", headers=headers)
    assert all(item["id"] != track_id for item in list_response.json()["items"])


def test_delete_track_forbidden_without_edit_access(client):
    owner_headers = _register(client, "track-del-owner@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Protected", "geom": _LINE_B}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-del-other@example.test")
    response = client.delete(f"/tracks/{track_id}", headers=other_headers)
    assert response.status_code == 403
