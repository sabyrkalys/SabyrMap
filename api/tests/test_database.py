from sqlalchemy.orm import sessionmaker

import app.database as database_module
from app.models.organization import Organization


def test_get_db_commits_on_success(db_engine, monkeypatch):
    TestSessionLocal = sessionmaker(bind=db_engine)
    monkeypatch.setattr(database_module, "SessionLocal", TestSessionLocal)

    gen = database_module.get_db()
    db = next(gen)
    db.add(Organization(name="get-db-commit-test", plan="personal"))
    try:
        next(gen)
    except StopIteration:
        pass

    check = TestSessionLocal()
    try:
        persisted = check.query(Organization).filter_by(name="get-db-commit-test").first()
        assert persisted is not None
    finally:
        check.query(Organization).filter_by(name="get-db-commit-test").delete()
        check.commit()
        check.close()


def test_get_db_rolls_back_on_exception(db_engine, monkeypatch):
    TestSessionLocal = sessionmaker(bind=db_engine)
    monkeypatch.setattr(database_module, "SessionLocal", TestSessionLocal)

    gen = database_module.get_db()
    db = next(gen)
    db.add(Organization(name="get-db-rollback-test", plan="personal"))

    raised = False
    try:
        gen.throw(RuntimeError("boom"))
    except RuntimeError:
        raised = True
    assert raised

    check = TestSessionLocal()
    try:
        persisted = check.query(Organization).filter_by(name="get-db-rollback-test").first()
        assert persisted is None
    finally:
        check.close()
