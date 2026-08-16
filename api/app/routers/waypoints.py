import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.user import User
from app.models.waypoint import Waypoint
from app.schemas.geometry import geojson_to_point, point_to_geojson
from app.schemas.waypoints import WaypointCreateRequest, WaypointListResponse, WaypointResponse, WaypointUpdateRequest
from app.services.authorization import can_edit_resource, can_view_resource
from app.services.resources import create_waypoint

router = APIRouter(prefix="/waypoints", tags=["waypoints"])


def _to_response(resource: Resource, waypoint: Waypoint) -> WaypointResponse:
    return WaypointResponse(
        id=waypoint.id,
        org_id=resource.org_id,
        owner_id=resource.owner_id,
        name=waypoint.name,
        geom=point_to_geojson(waypoint.geom),
        created_at=resource.created_at,
    )


def _get_resource_and_waypoint(db: Session, waypoint_id: uuid.UUID) -> tuple[Resource, Waypoint]:
    resource = (
        db.query(Resource)
        .filter(Resource.id == waypoint_id, Resource.deleted_at.is_(None))
        .first()
    )
    waypoint = db.get(Waypoint, waypoint_id) if resource is not None else None
    if resource is None or waypoint is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Waypoint not found")
    return resource, waypoint


@router.post("", response_model=WaypointResponse, status_code=status.HTTP_201_CREATED)
def create(
    payload: WaypointCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    waypoint = create_waypoint(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_point(payload.geom),
    )
    resource = db.get(Resource, waypoint.id)
    return _to_response(resource, waypoint)


@router.get("", response_model=WaypointListResponse)
def list_waypoints(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resources = (
        db.query(Resource)
        .filter(
            Resource.resource_type == ResourceType.WAYPOINT,
            Resource.deleted_at.is_(None),
            Resource.org_id == current_user.org_id,
        )
        .order_by(Resource.created_at)
        .all()
    )
    visible = [r for r in resources if can_view_resource(db, current_user, r)]
    page = visible[offset : offset + limit]
    items = [_to_response(resource, db.get(Waypoint, resource.id)) for resource in page]
    return WaypointListResponse(items=items, limit=limit, offset=offset)


@router.get("/{waypoint_id}", response_model=WaypointResponse)
def get_waypoint(
    waypoint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_view_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this waypoint")
    return _to_response(resource, waypoint)


@router.patch("/{waypoint_id}", response_model=WaypointResponse)
def update_waypoint(
    waypoint_id: uuid.UUID,
    payload: WaypointUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to edit this waypoint")

    if payload.name is not None:
        waypoint.name = payload.name
    if payload.geom is not None:
        waypoint.geom = geojson_to_point(payload.geom)
    db.flush()
    return _to_response(resource, waypoint)


@router.delete("/{waypoint_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_waypoint(
    waypoint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to delete this waypoint")

    resource.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return None
