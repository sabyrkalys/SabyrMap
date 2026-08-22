def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_create_and_get_waypoint(client):
    headers = _register(client, "waypoint-create@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Trailhead", "type": "generic", "geom": {"type": "Point", "coordinates": [7.6, 45.9]}},
        headers=headers,
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Trailhead"
    assert body["geom"] == {"type": "Point", "coordinates": [7.6, 45.9]}

    get_response = client.get(f"/waypoints/{body['id']}", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["id"] == body["id"]


def test_list_waypoints_returns_created(client):
    headers = _register(client, "waypoint-list@example.test")
    client.post(
        "/waypoints",
        json={"name": "A", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 2.0]}},
        headers=headers,
    )
    response = client.get("/waypoints", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 50
    assert body["offset"] == 0
    assert any(item["name"] == "A" for item in body["items"])


def test_get_waypoint_not_found(client):
    import uuid

    headers = _register(client, "waypoint-404@example.test")
    response = client.get(f"/waypoints/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_get_waypoint_forbidden_for_other_org(client):
    owner_headers = _register(client, "waypoint-owner-a@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Secret", "type": "generic", "geom": {"type": "Point", "coordinates": [3.0, 4.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-owner-b@example.test")
    response = client.get(f"/waypoints/{waypoint_id}", headers=other_headers)
    assert response.status_code == 403


def test_create_waypoint_rejects_empty_name(client):
    headers = _register(client, "waypoint-empty-name@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 422


def test_create_waypoint_rejects_wrong_geometry_type(client):
    headers = _register(client, "waypoint-badgeom@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Bad",
            "type": "generic",
            "geom": {"type": "LineString", "coordinates": [[1.0, 2.0], [3.0, 4.0]]},
        },
        headers=headers,
    )
    assert response.status_code == 422


def test_list_waypoints_pagination(client):
    headers = _register(client, "waypoint-page@example.test")
    for i in range(3):
        client.post(
            "/waypoints",
            json={"name": f"P{i}", "type": "generic", "geom": {"type": "Point", "coordinates": [float(i), float(i)]}},
            headers=headers,
        )
    response = client.get("/waypoints?limit=2&offset=1", headers=headers)
    body = response.json()
    assert len(body["items"]) == 2
    assert body["limit"] == 2
    assert body["offset"] == 1


def test_update_waypoint_name_only(client):
    headers = _register(client, "waypoint-update@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Old", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"name": "New"}, headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "New"
    assert body["geom"] == {"type": "Point", "coordinates": [1.0, 1.0]}


def test_update_waypoint_forbidden_without_edit_access(client):
    owner_headers = _register(client, "waypoint-edit-owner@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Mine", "type": "generic", "geom": {"type": "Point", "coordinates": [2.0, 2.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-edit-other@example.test")
    response = client.patch(f"/waypoints/{waypoint_id}", json={"name": "Hacked"}, headers=other_headers)
    assert response.status_code == 403


def test_delete_waypoint_soft_deletes(client):
    headers = _register(client, "waypoint-delete@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Gone", "type": "generic", "geom": {"type": "Point", "coordinates": [5.0, 5.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    delete_response = client.delete(f"/waypoints/{waypoint_id}", headers=headers)
    assert delete_response.status_code == 204

    get_response = client.get(f"/waypoints/{waypoint_id}", headers=headers)
    assert get_response.status_code == 404

    list_response = client.get("/waypoints", headers=headers)
    assert all(item["id"] != waypoint_id for item in list_response.json()["items"])


def test_delete_waypoint_forbidden_without_edit_access(client):
    owner_headers = _register(client, "waypoint-del-owner@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Protected", "type": "generic", "geom": {"type": "Point", "coordinates": [6.0, 6.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-del-other@example.test")
    response = client.delete(f"/waypoints/{waypoint_id}", headers=other_headers)
    assert response.status_code == 403


def test_create_waypoint_rejects_empty_type(client):
    headers = _register(client, "waypoint-empty-type@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Valid", "type": "", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 422
