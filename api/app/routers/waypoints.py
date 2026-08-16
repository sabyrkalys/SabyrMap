from app.models.enums import ResourceType
from app.models.waypoint import Waypoint
from app.routers.resource_crud import build_resource_router
from app.schemas.geometry import geojson_to_point, point_to_geojson
from app.schemas.waypoints import WaypointCreateRequest, WaypointListResponse, WaypointResponse, WaypointUpdateRequest
from app.services.resources import create_waypoint

router = build_resource_router(
    prefix="/waypoints",
    tags=["waypoints"],
    entity_name="waypoint",
    resource_type=ResourceType.WAYPOINT,
    model=Waypoint,
    create_service=create_waypoint,
    create_request_schema=WaypointCreateRequest,
    update_request_schema=WaypointUpdateRequest,
    response_schema=WaypointResponse,
    list_response_schema=WaypointListResponse,
    geom_to_wire=point_to_geojson,
    wire_to_geom=geojson_to_point,
)
