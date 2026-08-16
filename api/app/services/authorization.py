from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.models.enums import Permission, Role, ShareScope
from app.models.resource import Resource
from app.models.resource_share import ResourceShare
from app.models.user import User


def can_view_resource(db: Session, user: User, resource: Resource) -> bool:
    if user.deleted_at is not None:
        return False
    if resource.deleted_at is not None:
        return False
    if resource.org_id != user.org_id:
        return False
    if resource.owner_id == user.id:
        return True
    if user.role in (Role.OWNER, Role.ADMIN):
        return True

    share_exists = (
        db.query(ResourceShare)
        .filter(
            ResourceShare.resource_id == resource.id,
            or_(
                ResourceShare.scope == ShareScope.ORGANIZATION,
                and_(
                    ResourceShare.scope == ShareScope.USER,
                    ResourceShare.shared_with_user_id == user.id,
                ),
            ),
        )
        .first()
    )
    return share_exists is not None


def can_edit_resource(db: Session, user: User, resource: Resource) -> bool:
    if user.deleted_at is not None:
        return False
    if resource.deleted_at is not None:
        return False
    if resource.org_id != user.org_id:
        return False
    if resource.owner_id == user.id:
        return True

    share_exists = (
        db.query(ResourceShare)
        .filter(
            ResourceShare.resource_id == resource.id,
            ResourceShare.permission == Permission.EDIT,
            or_(
                ResourceShare.scope == ShareScope.ORGANIZATION,
                and_(
                    ResourceShare.scope == ShareScope.USER,
                    ResourceShare.shared_with_user_id == user.id,
                ),
            ),
        )
        .first()
    )
    return share_exists is not None
