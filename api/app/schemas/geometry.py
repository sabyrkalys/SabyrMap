from typing import Literal

from geoalchemy2.elements import WKBElement
from geoalchemy2.shape import from_shape, to_shape
from pydantic import BaseModel, field_validator
from shapely.geometry import LineString, Point


class GeoJSONPoint(BaseModel):
    type: Literal["Point"] = "Point"
    coordinates: tuple[float, float]


class GeoJSONLineString(BaseModel):
    type: Literal["LineString"] = "LineString"
    coordinates: list[tuple[float, float]]

    @field_validator("coordinates")
    @classmethod
    def _min_two_points(cls, v: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(v) < 2:
            raise ValueError("LineString requires at least 2 coordinates")
        return v


def point_to_geojson(geom: WKBElement) -> GeoJSONPoint:
    shape = to_shape(geom)
    return GeoJSONPoint(coordinates=(shape.x, shape.y))


def geojson_to_point(geo: GeoJSONPoint) -> WKBElement:
    return from_shape(Point(geo.coordinates[0], geo.coordinates[1]), srid=4326)


def linestring_to_geojson(geom: WKBElement) -> GeoJSONLineString:
    shape = to_shape(geom)
    return GeoJSONLineString(coordinates=[(x, y) for x, y in shape.coords])


def geojson_to_linestring(geo: GeoJSONLineString) -> WKBElement:
    return from_shape(LineString(geo.coordinates), srid=4326)
