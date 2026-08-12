from app.models.organization import Organization


def test_create_organization(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    assert org.id is not None
    assert org.name == "Acme Corp"
    assert org.plan == "free"
    assert org.limits_json == {}
    assert org.created_at is not None
