import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.services.auth import hash_password, verify_password
from app.services.organizations import create_personal_organization_and_owner

SINGLE_EMAIL = "single-user@example.test"


def _make_app(db_session):
    app = FastAPI()

    @app.get("/whoami")
    def whoami(user: User = Depends(get_current_user)):
        return {"id": str(user.id), "email": user.email}

    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    return app


@pytest.fixture()
def single_user_mode(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_DISABLED", True)
    monkeypatch.setattr(settings, "SINGLE_USER_EMAIL", SINGLE_EMAIL)


def test_request_without_header_succeeds_and_creates_the_user(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.status_code == 200
    assert response.json()["email"] == SINGLE_EMAIL
    assert db_session.query(User).filter(User.email == SINGLE_EMAIL).count() == 1


def test_repeated_requests_return_the_same_user(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    first = client.get("/whoami").json()
    second = client.get("/whoami").json()

    assert first["id"] == second["id"]
    assert db_session.query(User).filter(User.email == SINGLE_EMAIL).count() == 1


def test_garbage_token_is_ignored(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami", headers={"Authorization": "Bearer garbage"})

    assert response.status_code == 200
    assert response.json()["email"] == SINGLE_EMAIL


def test_existing_active_user_is_reused(db_session, single_user_mode):
    existing = create_personal_organization_and_owner(
        db_session, email=SINGLE_EMAIL, password_hash=hash_password("whatever")
    )
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.json()["id"] == str(existing.id)


def test_created_user_has_a_valid_but_unguessable_password_hash(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))
    client.get("/whoami")
    user = db_session.query(User).filter(User.email == SINGLE_EMAIL).one()

    # Must be a well-formed bcrypt hash (so POST /auth/login for this email
    # returns 401 instead of crashing), and must not match trivial passwords.
    assert verify_password("", user.password_hash) is False
    assert verify_password("password", user.password_hash) is False


def test_flag_off_still_requires_a_token(db_session):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.status_code == 401
