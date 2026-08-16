from app.models.enums import ResourceType
from app.models.track import Track
from app.routers.resource_crud import build_resource_router
from app.schemas.geometry import geojson_to_linestring, linestring_to_geojson
from app.schemas.tracks import TrackCreateRequest, TrackListResponse, TrackResponse, TrackUpdateRequest
from app.services.resources import create_track

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
)
