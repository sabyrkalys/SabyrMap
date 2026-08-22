import uuid
from datetime import datetime, timezone
from typing import Any, Callable, Type

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.user import User
from app.services.authorization import can_edit_resource, can_view_resource


def get_resource_and_entity(
    db: Session, model: Type[Any], entity_id: uuid.UUID, entity_label: str
) -> tuple[Resource, Any]:
    """Get a Resource and its associated entity by ID, raising HTTPException(404) if not found.

    Queries the Resource table and the entity model table, returning both if both exist
    and the resource has not been soft-deleted.
    """
    resource = (
        db.query(Resource)
        .filter(Resource.id == entity_id, Resource.deleted_at.is_(None))
        .first()
    )
    entity = db.get(model, entity_id) if resource is not None else None
    if resource is None or entity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{entity_label} not found")
    return resource, entity


def build_resource_router(
    *,
    prefix: str,
    tags: list[str],
    entity_name: str,
    resource_type: ResourceType,
    model: Type[Any],
    create_service: Callable[..., Any],
    create_request_schema: Type[Any],
    update_request_schema: Type[Any],
    response_schema: Type[Any],
    list_response_schema: Type[Any],
    geom_to_wire: Callable[[Any], Any],
    wire_to_geom: Callable[[Any], Any],
) -> APIRouter:
    """Build a CRUD router for a resource-backed entity (waypoint, track, ...).

    All resource-backed entities share the same shape: a `Resource` row plus a
    child table with `name`/`geom`, gated by `can_view_resource`/`can_edit_resource`,
    with soft delete and offset/limit pagination. Only the entity-specific pieces
    (model class, geometry conversion, create service, schemas) vary.
    """

    router = APIRouter(prefix=prefix, tags=tags)
    entity_label = entity_name.capitalize()

    def _to_response(resource: Resource, entity: Any):
        return response_schema(
            id=entity.id,
            org_id=resource.org_id,
            owner_id=resource.owner_id,
            name=entity.name,
            geom=geom_to_wire(entity.geom),
            created_at=resource.created_at,
        )

    def _get_resource_and_entity(db: Session, entity_id: uuid.UUID) -> tuple[Resource, Any]:
        return get_resource_and_entity(db, model, entity_id, entity_label)

    @router.post("", response_model=response_schema, status_code=status.HTTP_201_CREATED)
    def create(
        payload: create_request_schema,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        entity = create_service(
            db,
            org_id=current_user.org_id,
            owner_id=current_user.id,
            name=payload.name,
            geom=wire_to_geom(payload.geom),
        )
        resource = db.get(Resource, entity.id)
        return _to_response(resource, entity)

    @router.get("", response_model=list_response_schema)
    def list_entities(
        limit: int = Query(default=50, ge=1, le=200),
        offset: int = Query(default=0, ge=0),
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        resources = (
            db.query(Resource)
            .filter(
                Resource.resource_type == resource_type,
                Resource.deleted_at.is_(None),
                Resource.org_id == current_user.org_id,
            )
            .order_by(Resource.created_at)
            .all()
        )
        visible = [r for r in resources if can_view_resource(db, current_user, r)]
        page = visible[offset : offset + limit]
        items = [_to_response(resource, db.get(model, resource.id)) for resource in page]
        return list_response_schema(items=items, limit=limit, offset=offset)

    @router.get("/{resource_id}", response_model=response_schema)
    def get_entity(
        resource_id: uuid.UUID,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        resource, entity = _get_resource_and_entity(db, resource_id)
        if not can_view_resource(db, current_user, resource):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail=f"Not allowed to view this {entity_name}"
            )
        return _to_response(resource, entity)

    @router.patch("/{resource_id}", response_model=response_schema)
    def update_entity(
        resource_id: uuid.UUID,
        payload: update_request_schema,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        resource, entity = _get_resource_and_entity(db, resource_id)
        if not can_edit_resource(db, current_user, resource):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail=f"Not allowed to edit this {entity_name}"
            )

        if payload.name is not None:
            entity.name = payload.name
        if payload.geom is not None:
            entity.geom = wire_to_geom(payload.geom)
        db.flush()
        return _to_response(resource, entity)

    @router.delete("/{resource_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_entity(
        resource_id: uuid.UUID,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        resource, entity = _get_resource_and_entity(db, resource_id)
        if not can_edit_resource(db, current_user, resource):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail=f"Not allowed to delete this {entity_name}"
            )

        resource.deleted_at = datetime.now(timezone.utc)
        db.flush()
        return None

    return router
