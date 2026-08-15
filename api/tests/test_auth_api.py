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
