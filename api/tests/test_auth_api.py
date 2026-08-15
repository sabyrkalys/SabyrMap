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
