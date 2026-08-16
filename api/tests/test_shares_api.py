import uuid

from app.models.enums import Role
from app.models.organization import Organization
from app.models.user import User
from app.services.auth import create_access_token


def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _create_waypoint(client, headers, name="Shared Point"):
    response = client.post(
        "/waypoints",
        json={"name": name, "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    return response.json()["id"]


def _add_org_member(db_session, org_id, email, role=Role.MEMBER):
    user = User(org_id=org_id, email=email, password_hash="not-a-real-hash", role=role)
    db_session.add(user)
    db_session.flush()
    return user


def _auth_headers_for(user):
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def test_owner_can_create_organization_scope_share(client):
    headers = _register(client, "share-owner@example.test")
    waypoint_id = _create_waypoint(client, headers)

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["scope"] == "organization"
    assert body["shared_with_user_id"] is None


def test_edit_shared_user_can_also_create_shares(client, db_session):
    owner_headers = _register(client, "share-owner-2@example.test")
    waypoint_id = _create_waypoint(client, owner_headers)

    owner = db_session.query(User).filter_by(email="share-owner-2@example.test").one()
    editor = _add_org_member(db_session, owner.org_id, "share-editor@example.test")

    grant_response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "edit", "shared_with_user_id": str(editor.id)},
        headers=owner_headers,
    )
    assert grant_response.status_code == 201

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=_auth_headers_for(editor),
    )
    assert response.status_code == 201


def test_view_shared_user_cannot_create_shares(client, db_session):
    owner_headers = _register(client, "share-owner-3@example.test")
    waypoint_id = _create_waypoint(client, owner_headers)

    owner = db_session.query(User).filter_by(email="share-owner-3@example.test").one()
    viewer = _add_org_member(db_session, owner.org_id, "share-viewer@example.test")

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(viewer.id)},
        headers=owner_headers,
    )

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=_auth_headers_for(viewer),
    )
    assert response.status_code == 403


def test_list_shares(client):
    headers = _register(client, "share-owner-4@example.test")
    waypoint_id = _create_waypoint(client, headers)
    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )

    response = client.get(f"/resources/{waypoint_id}/shares", headers=headers)
    assert response.status_code == 200
    assert len(response.json()["items"]) == 1


def test_delete_share(client):
    headers = _register(client, "share-owner-5@example.test")
    waypoint_id = _create_waypoint(client, headers)
    create_response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    share_id = create_response.json()["id"]

    delete_response = client.delete(f"/resources/{waypoint_id}/shares/{share_id}", headers=headers)
    assert delete_response.status_code == 204

    list_response = client.get(f"/resources/{waypoint_id}/shares", headers=headers)
    assert list_response.json()["items"] == []


def test_share_to_user_outside_org_rejected(client, db_session):
    headers = _register(client, "share-owner-6@example.test")
    waypoint_id = _create_waypoint(client, headers)

    other_org = Organization(name="Other Org", plan="personal")
    db_session.add(other_org)
    db_session.flush()
    outsider = _add_org_member(db_session, other_org.id, "outsider@example.test")

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(outsider.id)},
        headers=headers,
    )
    assert response.status_code == 422


def test_share_scope_target_mismatch_rejected(client):
    headers = _register(client, "share-owner-7@example.test")
    waypoint_id = _create_waypoint(client, headers)

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view", "shared_with_user_id": str(uuid.uuid4())},
        headers=headers,
    )
    assert response.status_code == 422


def test_create_share_on_nonexistent_resource_404(client):
    headers = _register(client, "share-owner-8@example.test")
    response = client.post(
        f"/resources/{uuid.uuid4()}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    assert response.status_code == 404
