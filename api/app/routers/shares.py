import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import Permission as OrmPermission, ShareScope as OrmShareScope
from app.models.resource import Resource
from app.models.resource_share import ResourceShare
from app.models.user import User
from app.schemas.shares import Permission, ShareCreateRequest, ShareListResponse, ShareResponse, ShareScope
from app.services.authorization import can_edit_resource

router = APIRouter(prefix="/resources", tags=["shares"])


def _get_resource(db: Session, resource_id: uuid.UUID) -> Resource:
    resource = (
        db.query(Resource)
        .filter(Resource.id == resource_id, Resource.deleted_at.is_(None))
        .first()
    )
    if resource is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Resource not found")
    return resource


def _require_edit(db: Session, current_user: User, resource: Resource) -> None:
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to manage sharing for this resource",
        )


def _to_response(share: ResourceShare) -> ShareResponse:
    return ShareResponse(
        id=share.id,
        resource_id=share.resource_id,
        scope=ShareScope(share.scope.value),
        permission=Permission(share.permission.value),
        shared_with_user_id=share.shared_with_user_id,
        created_by=share.created_by,
        created_at=share.created_at,
    )


@router.post("/{resource_id}/shares", response_model=ShareResponse)
def create_share(
    resource_id: uuid.UUID,
    payload: ShareCreateRequest,
    response: Response,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    if payload.shared_with_user_id is not None:
        target = (
            db.query(User)
            .filter(User.id == payload.shared_with_user_id, User.deleted_at.is_(None))
            .first()
        )
        if target is None or target.org_id != resource.org_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="shared_with_user_id must belong to the resource's organization",
            )

        existing = (
            db.query(ResourceShare)
            .filter(
                ResourceShare.resource_id == resource.id,
                ResourceShare.shared_with_user_id == payload.shared_with_user_id,
            )
            .first()
        )
    else:
        existing = (
            db.query(ResourceShare)
            .filter(
                ResourceShare.resource_id == resource.id,
                ResourceShare.scope == OrmShareScope.ORGANIZATION,
            )
            .first()
        )

    if existing is not None:
        existing.scope = OrmShareScope(payload.scope.value)
        existing.permission = OrmPermission(payload.permission.value)
        db.flush()
        response.status_code = status.HTTP_200_OK
        return _to_response(existing)

    share = ResourceShare(
        resource_id=resource.id,
        shared_with_user_id=payload.shared_with_user_id,
        scope=OrmShareScope(payload.scope.value),
        permission=OrmPermission(payload.permission.value),
        created_by=current_user.id,
    )
    db.add(share)
    db.flush()
    response.status_code = status.HTTP_201_CREATED
    return _to_response(share)


@router.get("/{resource_id}/shares", response_model=ShareListResponse)
def list_shares(
    resource_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    shares = db.query(ResourceShare).filter(ResourceShare.resource_id == resource.id).all()
    return ShareListResponse(items=[_to_response(s) for s in shares])


@router.delete("/{resource_id}/shares/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_share(
    resource_id: uuid.UUID,
    share_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    share = (
        db.query(ResourceShare)
        .filter(ResourceShare.id == share_id, ResourceShare.resource_id == resource.id)
        .first()
    )
    if share is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Share not found")

    db.delete(share)
    db.flush()
    return None
