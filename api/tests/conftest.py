import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg2
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.database import Base
from app.main import app

TEST_DB_NAME = "alpinequest_test"


def _admin_url():
    # same server as DATABASE_URL, connect to maintenance db "postgres"
    base = settings.DATABASE_URL.rsplit("/", 1)[0]
    return f"{base}/postgres"


def _test_db_url():
    base = settings.DATABASE_URL.rsplit("/", 1)[0]
    return f"{base}/{TEST_DB_NAME}"


@pytest.fixture(scope="session")
def db_engine():
    admin_conn = psycopg2.connect(_admin_url())
    admin_conn.autocommit = True
    with admin_conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (TEST_DB_NAME,))
        if cur.fetchone() is None:
            cur.execute(f"CREATE DATABASE {TEST_DB_NAME}")
    admin_conn.close()

    engine = create_engine(_test_db_url())
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
    Base.metadata.create_all(bind=engine)

    yield engine

    Base.metadata.drop_all(bind=engine)
    engine.dispose()


@pytest.fixture()
def db_session(db_engine):
    connection = db_engine.connect()
    transaction = connection.begin()
    Session = sessionmaker(bind=connection)
    session = Session()

    yield session

    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture()
def client(db_session):
    from app.database import get_db

    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    yield TestClient(app)
    app.dependency_overrides.clear()
