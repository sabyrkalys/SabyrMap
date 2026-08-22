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
    assert body["type"] == "generic"
    assert body["note"] is None
    assert body["can_edit"] is True
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


def test_create_waypoint_with_note(client):
    headers = _register(client, "waypoint-note@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Camp",
            "type": "camp",
            "note": "Bring extra water",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["note"] == "Bring extra water"


def test_create_waypoint_with_empty_note_stores_null(client):
    headers = _register(client, "waypoint-empty-note@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Camp", "type": "camp", "note": "", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["note"] is None


def test_update_waypoint_type_and_note(client):
    headers = _register(client, "waypoint-update-type@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Spot", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(
        f"/waypoints/{waypoint_id}",
        json={"type": "danger", "note": "Rockslide area"},
        headers=headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["type"] == "danger"
    assert body["note"] == "Rockslide area"
    assert body["name"] == "Spot"


def test_update_waypoint_clears_note_with_empty_string(client):
    headers = _register(client, "waypoint-clear-note@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Spot", "type": "generic", "note": "temporary", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"note": ""}, headers=headers)
    assert response.status_code == 200
    assert response.json()["note"] is None


def test_can_edit_true_for_owner(client):
    headers = _register(client, "waypoint-can-edit-owner@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Mine", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.json()["can_edit"] is True


def test_can_edit_true_for_edit_share(client, db_session):
    from app.models.enums import Role
    from app.models.user import User
    from app.services.auth import create_access_token

    owner_headers = _register(client, "waypoint-can-edit-owner-2@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Shared", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    owner = db_session.query(User).filter_by(email="waypoint-can-edit-owner-2@example.test").one()
    editor = User(org_id=owner.org_id, email="waypoint-can-edit-editor@example.test", password_hash="x", role=Role.MEMBER)
    db_session.add(editor)
    db_session.flush()

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "edit", "shared_with_user_id": str(editor.id)},
        headers=owner_headers,
    )

    editor_headers = {"Authorization": f"Bearer {create_access_token(editor.id)}"}
    response = client.get(f"/waypoints/{waypoint_id}", headers=editor_headers)
    assert response.json()["can_edit"] is True


def test_can_edit_false_for_view_share(client, db_session):
    from app.models.enums import Role
    from app.models.user import User
    from app.services.auth import create_access_token

    owner_headers = _register(client, "waypoint-can-edit-owner-3@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Shared", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    owner = db_session.query(User).filter_by(email="waypoint-can-edit-owner-3@example.test").one()
    viewer = User(org_id=owner.org_id, email="waypoint-can-edit-viewer@example.test", password_hash="x", role=Role.MEMBER)
    db_session.add(viewer)
    db_session.flush()

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(viewer.id)},
        headers=owner_headers,
    )

    viewer_headers = {"Authorization": f"Bearer {create_access_token(viewer.id)}"}
    response = client.get(f"/waypoints/{waypoint_id}", headers=viewer_headers)
    assert response.json()["can_edit"] is False
