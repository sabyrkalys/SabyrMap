from geoalchemy2.shape import to_shape

from app.models.enums import ResourceType
from app.models.track import Track
from app.routers.resource_crud import build_resource_router
from app.schemas.geometry import geojson_to_linestring, linestring_to_geojson
from app.schemas.tracks import TrackCreateRequest, TrackListResponse, TrackResponse, TrackUpdateRequest
from app.services.resources import create_track
from app.services.track_measurements import compute_elevation_gain_meters, compute_length_meters


def _extra_create_kwargs(payload: TrackCreateRequest) -> dict:
    return {"started_at": payload.started_at, "finished_at": payload.finished_at}


def _apply_extra_update(entity: Track, payload: TrackUpdateRequest) -> None:
    if payload.started_at is not None:
        entity.started_at = payload.started_at
    if payload.finished_at is not None:
        entity.finished_at = payload.finished_at


def _extra_response_fields(entity: Track) -> dict:
    coords = list(to_shape(entity.geom).coords)
    has_timing = entity.started_at is not None
    duration_seconds = (
        int((entity.finished_at - entity.started_at).total_seconds())
        if entity.started_at is not None and entity.finished_at is not None
        else None
    )
    return {
        "length_meters": compute_length_meters(coords),
        "duration_seconds": duration_seconds,
        "elevation_gain_meters": compute_elevation_gain_meters(coords) if has_timing else None,
    }


router = build_resource_router(
    prefix="/tracks",
    tags=["tracks"],
    entity_name="track",
    resource_type=ResourceType.TRACK,
    model=Track,
    create_service=create_track,
    create_request_schema=TrackCreateRequest,
    update_request_schema=TrackUpdateRequest,
    response_schema=TrackResponse,
    list_response_schema=TrackListResponse,
    geom_to_wire=linestring_to_geojson,
    wire_to_geom=geojson_to_linestring,
    extra_create_kwargs=_extra_create_kwargs,
    apply_extra_update=_apply_extra_update,
    extra_response_fields=_extra_response_fields,
)
