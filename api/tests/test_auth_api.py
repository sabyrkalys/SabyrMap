def test_register_returns_token(client):
    response = client.post(
        "/auth/register",
        json={"email": "new-user@example.test", "password": "s3cret-pass"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert isinstance(body["access_token"], str) and body["access_token"]


def test_register_rejects_duplicate_email(client):
    client.post(
        "/auth/register",
        json={"email": "dupe@example.test", "password": "s3cret-pass"},
    )

    response = client.post(
        "/auth/register",
        json={"email": "dupe@example.test", "password": "another-pass"},
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "Email already registered"}


def test_register_rejects_invalid_email(client):
    response = client.post(
        "/auth/register",
        json={"email": "not-an-email", "password": "s3cret-pass"},
    )
    assert response.status_code == 422


def test_register_rejects_empty_password(client):
    response = client.post(
        "/auth/register",
        json={"email": "empty-pass@example.test", "password": ""},
    )
    assert response.status_code == 422


def test_login_returns_token_for_correct_credentials(client):
    client.post(
        "/auth/register",
        json={"email": "login-user@example.test", "password": "s3cret-pass"},
    )

    response = client.post(
        "/auth/login",
        json={"email": "login-user@example.test", "password": "s3cret-pass"},
    )

    assert response.status_code == 200
    assert response.json()["token_type"] == "bearer"


def test_login_rejects_wrong_password(client):
    client.post(
        "/auth/register",
        json={"email": "wrong-pass@example.test", "password": "s3cret-pass"},
    )

    response = client.post(
        "/auth/login",
        json={"email": "wrong-pass@example.test", "password": "not-the-password"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


def test_login_rejects_unknown_email(client):
    response = client.post(
        "/auth/login",
        json={"email": "nobody@example.test", "password": "whatever"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


def test_login_rejects_soft_deleted_user(client, db_session):
    from datetime import datetime, timezone

    from app.models.user import User

    client.post(
        "/auth/register",
        json={"email": "deleted-user@example.test", "password": "s3cret-pass"},
    )
    user = db_session.query(User).filter_by(email="deleted-user@example.test").one()
    user.deleted_at = datetime.now(timezone.utc)
    db_session.flush()

    response = client.post(
        "/auth/login",
        json={"email": "deleted-user@example.test", "password": "s3cret-pass"},
    )

    assert response.status_code == 401


def test_me_returns_current_user(client):
    register_response = client.post(
        "/auth/register",
        json={"email": "me-user@example.test", "password": "s3cret-pass"},
    )
    token = register_response.json()["access_token"]

    response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "me-user@example.test"
    assert body["role"] == "owner"
    assert "org_id" in body


def test_me_rejects_missing_token(client):
    response = client.get("/auth/me")
    assert response.status_code == 401
    assert response.json() == {"detail": "Could not validate credentials"}


def test_me_rejects_invalid_token(client):
    response = client.get("/auth/me", headers={"Authorization": "Bearer garbage"})
    assert response.status_code == 401
