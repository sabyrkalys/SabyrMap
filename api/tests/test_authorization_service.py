from datetime import datetime, timezone

from app.models.enums import Permission, ResourceType, Role, ShareScope
from app.models.organization import Organization
from app.models.resource import Resource
from app.models.resource_share import ResourceShare
from app.models.user import User
from app.services.authorization import can_view_resource


def _setup(db_session, roles=("member",)):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()
    users = []
    for i, role in enumerate(roles):
        u = User(org_id=org.id, email=f"u{i}@acme.test", password_hash="h", role=role)
        db_session.add(u)
        users.append(u)
    db_session.flush()
    return org, users


def test_owner_can_view_own_resource(db_session):
    org, (member,) = _setup(db_session, roles=(Role.MEMBER,))
    resource = Resource(org_id=org.id, owner_id=member.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, member, resource) is True


def test_org_admin_can_view_others_resource(db_session):
    org, (creator, admin) = _setup(db_session, roles=(Role.MEMBER, Role.ADMIN))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, admin, resource) is True


def test_plain_member_cannot_view_others_resource_by_default(db_session):
    org, (creator, other_member) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, other_member, resource) is False


def test_user_scope_share_grants_access(db_session):
    org, (creator, viewer) = _setup(db_session, roles=(Role.MEMBER, Role.VIEWER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=viewer.id,
        scope=ShareScope.USER, permission=Permission.VIEW, created_by=creator.id,
    ))
    db_session.flush()

    assert can_view_resource(db_session, viewer, resource) is True


def test_organization_scope_share_grants_access_to_any_member(db_session):
    org, (creator, other_member) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=None,
        scope=ShareScope.ORGANIZATION, permission=Permission.VIEW, created_by=creator.id,
    ))
    db_session.flush()

    assert can_view_resource(db_session, other_member, resource) is True


def test_deleted_resource_is_never_visible(db_session):
    org, (member,) = _setup(db_session, roles=(Role.OWNER,))
    resource = Resource(
        org_id=org.id, owner_id=member.id, resource_type=ResourceType.WAYPOINT,
        deleted_at=datetime.now(timezone.utc),
    )
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, member, resource) is False


def test_user_scope_share_to_someone_else_does_not_grant_access(db_session):
    org, (creator, target, bystander) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=target.id,
        scope=ShareScope.USER, permission=Permission.VIEW, created_by=creator.id,
    ))
    db_session.flush()

    assert can_view_resource(db_session, bystander, resource) is False


def test_soft_deleted_user_cannot_view_own_resource(db_session):
    org, (member,) = _setup(db_session, roles=(Role.OWNER,))
    member.deleted_at = datetime.now(timezone.utc)
    db_session.flush()
    resource = Resource(org_id=org.id, owner_id=member.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, member, resource) is False


def test_resource_in_other_org_never_visible(db_session):
    org1, (member1,) = _setup(db_session, roles=(Role.OWNER,))
    org2 = Organization(name="Other Org", plan="free")
    db_session.add(org2)
    db_session.flush()
    other_owner = User(org_id=org2.id, email="cross@other.test", password_hash="h", role=Role.OWNER)
    db_session.add(other_owner)
    db_session.flush()
    resource = Resource(org_id=org2.id, owner_id=other_owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_view_resource(db_session, member1, resource) is False
