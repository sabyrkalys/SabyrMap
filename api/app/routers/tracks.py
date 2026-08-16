import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.track import Track
from app.models.user import User
from app.schemas.geometry import geojson_to_linestring, linestring_to_geojson
from app.schemas.tracks import TrackCreateRequest, TrackListResponse, TrackResponse, TrackUpdateRequest
from app.services.authorization import can_edit_resource, can_view_resource
from app.services.resources import create_track

router = APIRouter(prefix="/tracks", tags=["tracks"])


def _to_response(resource: Resource, track: Track) -> TrackResponse:
    return TrackResponse(
        id=track.id,
        org_id=resource.org_id,
        owner_id=resource.owner_id,
        name=track.name,
        geom=linestring_to_geojson(track.geom),
        created_at=resource.created_at,
    )


def _get_resource_and_track(db: Session, track_id: uuid.UUID) -> tuple[Resource, Track]:
    resource = (
        db.query(Resource)
        .filter(Resource.id == track_id, Resource.deleted_at.is_(None))
        .first()
    )
    track = db.get(Track, track_id) if resource is not None else None
    if resource is None or track is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Track not found")
    return resource, track


@router.post("", response_model=TrackResponse, status_code=status.HTTP_201_CREATED)
def create(
    payload: TrackCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    track = create_track(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_linestring(payload.geom),
    )
    resource = db.get(Resource, track.id)
    return _to_response(resource, track)


@router.get("", response_model=TrackListResponse)
def list_tracks(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resources = (
        db.query(Resource)
        .filter(Resource.resource_type == ResourceType.TRACK, Resource.deleted_at.is_(None))
        .order_by(Resource.created_at)
        .all()
    )
    visible = [r for r in resources if can_view_resource(db, current_user, r)]
    page = visible[offset : offset + limit]
    items = [_to_response(resource, db.get(Track, resource.id)) for resource in page]
    return TrackListResponse(items=items, limit=limit, offset=offset)


@router.get("/{track_id}", response_model=TrackResponse)
def get_track(
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_view_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this track")
    return _to_response(resource, track)


@router.patch("/{track_id}", response_model=TrackResponse)
def update_track(
    track_id: uuid.UUID,
    payload: TrackUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to edit this track")

    if payload.name is not None:
        track.name = payload.name
    if payload.geom is not None:
        track.geom = geojson_to_linestring(payload.geom)
    db.flush()
    return _to_response(resource, track)


@router.delete("/{track_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_track(
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to delete this track")

    resource.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return None
