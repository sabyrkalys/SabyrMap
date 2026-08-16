import pytest
from pydantic import ValidationError

from app.schemas.geometry import (
    GeoJSONLineString,
    GeoJSONPoint,
    geojson_to_linestring,
    geojson_to_point,
    linestring_to_geojson,
    point_to_geojson,
)


def test_point_roundtrip():
    original = GeoJSONPoint(coordinates=(7.6, 45.9))
    wkb = geojson_to_point(original)
    result = point_to_geojson(wkb)
    assert result.coordinates == (7.6, 45.9)


def test_linestring_roundtrip():
    original = GeoJSONLineString(coordinates=[(7.6, 45.9), (7.7, 46.0), (7.8, 46.05)])
    wkb = geojson_to_linestring(original)
    result = linestring_to_geojson(wkb)
    assert result.coordinates == [(7.6, 45.9), (7.7, 46.0), (7.8, 46.05)]


def test_linestring_rejects_single_point():
    with pytest.raises(ValidationError):
        GeoJSONLineString(coordinates=[(7.6, 45.9)])


def test_point_rejects_wrong_type_literal():
    with pytest.raises(ValidationError):
        GeoJSONPoint(type="LineString", coordinates=(1.0, 2.0))
