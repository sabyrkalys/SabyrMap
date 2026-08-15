from datetime import datetime, timezone

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import Role
from app.models.organization import Organization
from app.models.user import User
from app.services.auth import create_access_token


def _make_app(db_session):
    app = FastAPI()

    @app.get("/whoami")
    def whoami(user: User = Depends(get_current_user)):
        return {"id": str(user.id)}

    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    return app


def _create_user(db_session, email="dep-user@example.test"):
    org = Organization(name=email, plan="personal")
    db_session.add(org)
    db_session.flush()
    user = User(org_id=org.id, email=email, password_hash="hashed", role=Role.OWNER)
    db_session.add(user)
    db_session.flush()
    return user


def test_get_current_user_returns_user_for_valid_token(db_session):
    user = _create_user(db_session)
    token = create_access_token(user.id)
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    assert response.json() == {"id": str(user.id)}


def test_get_current_user_rejects_missing_header(db_session):
    client = TestClient(_make_app(db_session))
    response = client.get("/whoami")
    assert response.status_code == 401
    assert response.json() == {"detail": "Could not validate credentials"}


def test_get_current_user_rejects_invalid_token(db_session):
    client = TestClient(_make_app(db_session))
    response = client.get("/whoami", headers={"Authorization": "Bearer garbage"})
    assert response.status_code == 401


def test_get_current_user_rejects_soft_deleted_user(db_session):
    user = _create_user(db_session)
    token = create_access_token(user.id)
    user.deleted_at = datetime.now(timezone.utc)
    db_session.flush()
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
