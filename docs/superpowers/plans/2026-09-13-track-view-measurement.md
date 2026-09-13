# Track View & Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user see their saved GPS tracks in a list, open one to see it on a mini-map, and see its length, duration, and elevation gain.

**Architecture:** Backend: `tracks.geom` becomes 3D (`LINESTRING Z`), `tracks` gains nullable `started_at`/`finished_at`; `TrackResponse` gains computed (not stored) `length_meters`/`duration_seconds`/`elevation_gain_meters` fields, wired into the existing generic `build_resource_router` via new optional hook callables so `waypoints.py` (which doesn't use that router) is untouched. Frontend: the existing `tracks` Riverpod module gains the new fields end-to-end (capture → repository → model), plus two new read-only screens (`TracksListScreen`, `TrackDetailScreen`) reachable from a new `MapScreen` AppBar icon.

**Tech Stack:** FastAPI, SQLAlchemy + geoalchemy2 + Alembic, pytest (real Postgres/PostGIS test DB via `Base.metadata.create_all`); Flutter, Riverpod, maplibre_gl, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-13-track-view-measurement-design.md`

## Global Constraints

- `started_at`/`finished_at` are nullable and NOT backfilled for existing tracks; `duration_seconds` and `elevation_gain_meters` are `null` whenever `started_at` is `null` (pre-slice track) — the UI shows `—` for `null`.
- Track length is 2D ground (haversine) distance, ignoring elevation.
- Elevation gain uses a 3-meter noise threshold: only count `current - baseline` once it exceeds 3m, then reset baseline upward; never reset baseline on a drop (spec's "ignore drops").
- `TrackDetailScreen` is read-only for this slice — no rename/delete UI.
- Units: length as `"4.2 км"` (or `"NNN м"` under 1 km), duration as `"1 ч 25 мин"` (or `"NN мин"` under 1 hour, or `"—"` if null), elevation gain as `"+320 м"` (or `"—"` if null).
- No new third-party dependency for date/duration formatting — hand-rolled, matching `_defaultTrackName()`'s existing style in `map_screen.dart`.

---

### Task 1: `track_measurements.py` — length and elevation-gain pure functions

**Files:**
- Create: `api/app/services/track_measurements.py`
- Test: `api/tests/test_track_measurements.py`

**Interfaces:**
- Produces: `compute_length_meters(coords: list[tuple[float, float, float]]) -> float`, `compute_elevation_gain_meters(coords: list[tuple[float, float, float]]) -> float`. Both take a list of `(lon, lat, elevation)` tuples (the shape `shapely`'s `LineString.coords` yields for a `LINESTRING Z`). Used by Task 4's `tracks.py`.

- [ ] **Step 1: Write the failing tests**

```python
# api/tests/test_track_measurements.py
import pytest

from app.services.track_measurements import compute_elevation_gain_meters, compute_length_meters


def test_compute_length_meters_one_degree_of_latitude():
    coords = [(0.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    assert compute_length_meters(coords) == pytest.approx(111195, rel=1e-3)


def test_compute_length_meters_sums_multiple_segments():
    coords = [(0.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 2.0, 0.0)]
    single_segment = compute_length_meters([(0.0, 0.0, 0.0), (0.0, 1.0, 0.0)])
    assert compute_length_meters(coords) == pytest.approx(single_segment * 2, rel=1e-6)


def test_compute_length_meters_single_point_is_zero():
    assert compute_length_meters([(0.0, 0.0, 0.0)]) == 0.0


def test_compute_elevation_gain_monotonic_climb():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 105.0), (0.0, 0.0, 110.0), (0.0, 0.0, 115.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(15.0)


def test_compute_elevation_gain_ignores_noise_below_threshold():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 101.0), (0.0, 0.0, 99.0), (0.0, 0.0, 102.0), (0.0, 0.0, 100.0)]
    assert compute_elevation_gain_meters(coords) == 0.0


def test_compute_elevation_gain_climb_drop_climb_past_threshold():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 104.0), (0.0, 0.0, 101.0), (0.0, 0.0, 108.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(8.0)


def test_compute_elevation_gain_single_point_is_zero():
    assert compute_elevation_gain_meters([(0.0, 0.0, 100.0)]) == 0.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `api/`): `pytest tests/test_track_measurements.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.services.track_measurements'`

- [ ] **Step 3: Write the implementation**

```python
# api/app/services/track_measurements.py
import math

_EARTH_RADIUS_METERS = 6371000.0
_ELEVATION_NOISE_THRESHOLD_METERS = 3.0


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * _EARTH_RADIUS_METERS * math.asin(math.sqrt(a))


def compute_length_meters(coords: list[tuple[float, float, float]]) -> float:
    """2D ground distance along the track, ignoring elevation."""
    total = 0.0
    for (lon1, lat1, _), (lon2, lat2, _) in zip(coords, coords[1:]):
        total += _haversine_meters(lat1, lon1, lat2, lon2)
    return total


def compute_elevation_gain_meters(coords: list[tuple[float, float, float]]) -> float:
    """Sum of sustained climbs, smoothing GPS altitude noise with a 3m threshold.

    Tracks a baseline elevation; a delta only counts (and resets the baseline
    upward) once it exceeds the noise threshold, so small jitter is ignored.
    Drops never reset the baseline, so climbing back to a previous local peak
    doesn't double-count.
    """
    if len(coords) < 2:
        return 0.0
    gain = 0.0
    baseline = coords[0][2]
    for _, _, elevation in coords[1:]:
        delta = elevation - baseline
        if delta > _ELEVATION_NOISE_THRESHOLD_METERS:
            gain += delta
            baseline = elevation
    return gain
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_track_measurements.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add api/app/services/track_measurements.py api/tests/test_track_measurements.py
git commit -m "feat: add track length and elevation-gain calculation"
```

---

### Task 2: 3D coordinates in `GeoJSONLineString`

**Files:**
- Modify: `api/app/schemas/geometry.py`
- Modify: `api/tests/test_geometry_schemas.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `GeoJSONLineString.coordinates: list[tuple[float, float, float]]` (was `list[tuple[float, float]]`) — a breaking wire-format change consumed by Task 4's `tracks.py` schemas and the Flutter `HttpTracksRepository`/`Track.fromJson` (Tasks 5 and 8).

- [ ] **Step 1: Update the failing tests**

Replace the whole contents of `api/tests/test_geometry_schemas.py`:

```python
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
    original = GeoJSONLineString(
        coordinates=[(7.6, 45.9, 1200.0), (7.7, 46.0, 1250.5), (7.8, 46.05, 1300.0)]
    )
    wkb = geojson_to_linestring(original)
    result = linestring_to_geojson(wkb)
    assert result.coordinates == [(7.6, 45.9, 1200.0), (7.7, 46.0, 1250.5), (7.8, 46.05, 1300.0)]


def test_linestring_rejects_single_point():
    with pytest.raises(ValidationError):
        GeoJSONLineString(coordinates=[(7.6, 45.9, 1200.0)])


def test_linestring_rejects_2d_coordinates():
    with pytest.raises(ValidationError):
        GeoJSONLineString(coordinates=[(7.6, 45.9), (7.7, 46.0)])


def test_point_rejects_wrong_type_literal():
    with pytest.raises(ValidationError):
        GeoJSONPoint(type="LineString", coordinates=(1.0, 2.0))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_geometry_schemas.py -v`
Expected: FAIL — `test_linestring_roundtrip` fails because `linestring_to_geojson` still returns 2-tuples;
`test_linestring_rejects_2d_coordinates` fails because a 2-tuple is currently accepted.

- [ ] **Step 3: Update the implementation**

In `api/app/schemas/geometry.py`, change the `GeoJSONLineString` class and `linestring_to_geojson`:

```python
class GeoJSONLineString(BaseModel):
    type: Literal["LineString"] = "LineString"
    coordinates: list[tuple[float, float, float]]

    @field_validator("coordinates")
    @classmethod
    def _min_two_points(cls, v: list[tuple[float, float, float]]) -> list[tuple[float, float, float]]:
        if len(v) < 2:
            raise ValueError("LineString requires at least 2 coordinates")
        return v
```

```python
def linestring_to_geojson(geom: WKBElement) -> GeoJSONLineString:
    shape = to_shape(geom)
    return GeoJSONLineString(coordinates=[(x, y, z) for x, y, z in shape.coords])
```

`geojson_to_linestring` is unchanged — `shapely.geometry.LineString` already builds a 3D linestring from 3-tuples.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_geometry_schemas.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add api/app/schemas/geometry.py api/tests/test_geometry_schemas.py
git commit -m "feat: carry elevation as the third LineString coordinate"
```

---

### Task 3: `Track` model + migration — `started_at`/`finished_at` + `LINESTRING Z`

**Files:**
- Modify: `api/app/models/track.py`
- Create: `api/alembic/versions/<generated>_add_track_measurement_fields.py`

**Interfaces:**
- Produces: `Track.started_at: datetime | None`, `Track.finished_at: datetime | None`, and `Track.geom` now typed as a 3D linestring. Consumed by Task 4 (`services/resources.py`, `routers/tracks.py`).

- [ ] **Step 1: Update the `Track` model**

Replace `api/app/models/track.py`:

```python
import uuid
from datetime import datetime

from geoalchemy2 import Geometry
from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Track(Base):
    __tablename__ = "tracks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("resources.id"), primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    geom: Mapped[str] = mapped_column(
        Geometry(geometry_type="LINESTRINGZ", srid=4326, spatial_index=False), nullable=False
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

- [ ] **Step 2: Generate the migration skeleton**

Run (from `api/`): `alembic revision -m "add track measurement fields"`

This creates `api/alembic/versions/<hash>_add_track_measurement_fields.py` with `down_revision` already set to
the current head, `'45208d1707c8'` (verify: it must read `'45208d1707c8'` — if it doesn't, multiple heads
exist and must be resolved before continuing).

- [ ] **Step 3: Fill in `upgrade()`/`downgrade()`**

Edit the generated file so `upgrade()`/`downgrade()` read exactly:

```python
def upgrade() -> None:
    op.add_column("tracks", sa.Column("started_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("tracks", sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True))
    op.execute(
        "ALTER TABLE tracks ALTER COLUMN geom TYPE geometry(LINESTRINGZ, 4326) USING ST_Force3D(geom)"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE tracks ALTER COLUMN geom TYPE geometry(LINESTRING, 4326) USING ST_Force2D(geom)"
    )
    op.drop_column("tracks", "finished_at")
    op.drop_column("tracks", "started_at")
```

- [ ] **Step 4: Verify the migration directly against a real database (per `project_migration_test_gap` memory — pytest's schema comes from `Base.metadata.create_all`, NOT this migration, so a passing test suite is not proof this file does anything)**

Run against a scratch/dev database (not the `alpinequest_test` pytest DB, so it doesn't get dropped by the
test suite's teardown):

```bash
alembic upgrade head
psql "$DATABASE_URL" -c "\d tracks"
```

Expected: `geom` shows as `geometry(LineStringZ,4326)`, and `started_at`/`finished_at` show as
`timestamp with time zone`, nullable. Then:

```bash
alembic downgrade -1
psql "$DATABASE_URL" -c "\d tracks"
```

Expected: `geom` back to `geometry(LineString,4326)`, `started_at`/`finished_at` columns gone. Re-run
`alembic upgrade head` to leave the dev DB on the new schema.

- [ ] **Step 5: Commit**

```bash
git add api/app/models/track.py api/alembic/versions/*_add_track_measurement_fields.py
git commit -m "feat: add started_at/finished_at and 3D geometry to tracks table"
```

---

### Task 4: `build_resource_router` extension hooks + wire measurements into `tracks.py`

**Files:**
- Modify: `api/app/routers/resource_crud.py`
- Modify: `api/app/schemas/tracks.py`
- Modify: `api/app/services/resources.py`
- Modify: `api/app/routers/tracks.py`
- Modify: `api/tests/test_tracks_api.py`

**Interfaces:**
- Consumes: `compute_length_meters`/`compute_elevation_gain_meters` (Task 1),
  `GeoJSONLineString` 3-tuple coordinates (Task 2), `Track.started_at`/`finished_at` (Task 3).
- Produces: three new optional `build_resource_router(...)` keyword parameters —
  `extra_create_kwargs: Callable[[Any], dict] | None = None`,
  `apply_extra_update: Callable[[Any, Any], None] | None = None`,
  `extra_response_fields: Callable[[Any], dict] | None = None` (all default `None`, so `waypoints.py` — which
  doesn't call `build_resource_router` at all — is unaffected). `POST/PATCH /tracks` accept
  `started_at`/`finished_at`; `GET/POST/PATCH /tracks[...]` responses include `length_meters: float`,
  `duration_seconds: int | None`, `elevation_gain_meters: float | None`. Consumed by Flutter Tasks 5 and 8.

Note: the router-generic hooks and their track-specific use are done as one task rather than two, because
the hooks are inert (default `None`) until `tracks.py` uses them — splitting them would leave an
intermediate commit with no observable behavior to test against.

- [ ] **Step 1: Update existing tests to 3D coordinates and add new coverage (write first, since these will fail against the current 2D-only schema)**

Replace the top of `api/tests/test_tracks_api.py` (the two shared fixtures) and the two tests that use bare
2-element coordinate literals:

```python
_LINE_A = {"type": "LineString", "coordinates": [[7.6, 45.9, 0.0], [7.7, 46.0, 0.0], [7.8, 46.05, 0.0]]}
_LINE_B = {"type": "LineString", "coordinates": [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]]}
```

```python
def test_create_track_rejects_single_point_linestring(client):
    headers = _register(client, "track-shortline@example.test")
    response = client.post(
        "/tracks",
        json={"name": "TooShort", "geom": {"type": "LineString", "coordinates": [[1.0, 2.0, 0.0]]}},
        headers=headers,
    )
    assert response.status_code == 422
```

```python
def test_list_tracks_pagination(client):
    headers = _register(client, "track-page@example.test")
    for i in range(3):
        client.post(
            "/tracks",
            json={
                "name": f"T{i}",
                "geom": {
                    "type": "LineString",
                    "coordinates": [[float(i), float(i), 0.0], [float(i) + 1, float(i) + 1, 0.0]],
                },
            },
            headers=headers,
        )
    response = client.get("/tracks?limit=2&offset=1", headers=headers)
    body = response.json()
    assert len(body["items"]) == 2
    assert body["limit"] == 2
    assert body["offset"] == 1
```

Append new tests to the end of the file:

```python
def test_create_track_includes_computed_measurements(client):
    headers = _register(client, "track-measure@example.test")
    response = client.post(
        "/tracks",
        json={
            "name": "Ridge Loop",
            "geom": {
                "type": "LineString",
                "coordinates": [[0.0, 0.0, 100.0], [0.0, 1.0, 110.0]],
            },
            "started_at": "2026-09-13T08:00:00Z",
            "finished_at": "2026-09-13T09:30:00Z",
        },
        headers=headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["length_meters"] == pytest.approx(111195, rel=1e-3)
    assert body["duration_seconds"] == 5400
    assert body["elevation_gain_meters"] == pytest.approx(10.0)


def test_create_track_without_timing_has_null_duration_and_elevation(client):
    headers = _register(client, "track-notiming@example.test")
    response = client.post(
        "/tracks",
        json={"name": "Untimed", "geom": _LINE_B},
        headers=headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["duration_seconds"] is None
    assert body["elevation_gain_meters"] is None
    assert body["length_meters"] > 0


def test_update_track_timing_recomputes_duration(client):
    headers = _register(client, "track-update-timing@example.test")
    create_response = client.post(
        "/tracks",
        json={"name": "Untimed", "geom": _LINE_B},
        headers=headers,
    )
    track_id = create_response.json()["id"]
    assert create_response.json()["duration_seconds"] is None

    response = client.patch(
        f"/tracks/{track_id}",
        json={"started_at": "2026-09-13T08:00:00Z", "finished_at": "2026-09-13T08:10:00Z"},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["duration_seconds"] == 600
```

Add `import pytest` at the top of `api/tests/test_tracks_api.py` if not already present.

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_tracks_api.py -v`
Expected: most existing tests FAIL with a 422 (schema still expects 2-tuples) — `started_at`/`finished_at`
are rejected as unexpected fields on create/update, and the new tests fail on missing response keys or a
`TypeError` once `build_resource_router` is called with the new keyword arguments in Step 3 below.

- [ ] **Step 3: Implement the hooks, then wire them into the schema, service, and router**

First, `api/app/routers/resource_crud.py` — change `build_resource_router`'s signature and the three
functions that use its parameters:

```python
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
    extra_create_kwargs: Callable[[Any], dict] | None = None,
    apply_extra_update: Callable[[Any, Any], None] | None = None,
    extra_response_fields: Callable[[Any], dict] | None = None,
) -> APIRouter:
```

```python
    def _to_response(resource: Resource, entity: Any):
        fields = {
            "id": entity.id,
            "org_id": resource.org_id,
            "owner_id": resource.owner_id,
            "name": entity.name,
            "geom": geom_to_wire(entity.geom),
            "created_at": resource.created_at,
        }
        if extra_response_fields is not None:
            fields.update(extra_response_fields(entity))
        return response_schema(**fields)
```

```python
    @router.post("", response_model=response_schema, status_code=status.HTTP_201_CREATED)
    def create(
        payload: create_request_schema,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        extra_kwargs = extra_create_kwargs(payload) if extra_create_kwargs is not None else {}
        entity = create_service(
            db,
            org_id=current_user.org_id,
            owner_id=current_user.id,
            name=payload.name,
            geom=wire_to_geom(payload.geom),
            **extra_kwargs,
        )
        resource = db.get(Resource, entity.id)
        return _to_response(resource, entity)
```

```python
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
        if apply_extra_update is not None:
            apply_extra_update(entity, payload)
        db.flush()
        return _to_response(resource, entity)
```

Then, `api/app/schemas/tracks.py` — full replacement:

```python
import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.geometry import GeoJSONLineString


class TrackCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    geom: GeoJSONLineString
    started_at: datetime | None = None
    finished_at: datetime | None = None


class TrackUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    geom: GeoJSONLineString | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None


class TrackResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    geom: GeoJSONLineString
    created_at: datetime
    length_meters: float
    duration_seconds: int | None
    elevation_gain_meters: float | None


class TrackListResponse(BaseModel):
    items: list[TrackResponse]
    limit: int
    offset: int
```

`api/app/services/resources.py` — change `create_track`:

```python
def create_track(
    db: Session,
    *,
    org_id: uuid.UUID,
    owner_id: uuid.UUID,
    name: str,
    geom,
    started_at=None,
    finished_at=None,
) -> Track:
    resource = Resource(org_id=org_id, owner_id=owner_id, resource_type=ResourceType.TRACK)
    db.add(resource)
    db.flush()
    track = Track(id=resource.id, name=name, geom=geom, started_at=started_at, finished_at=finished_at)
    db.add(track)
    db.flush()
    return track
```

`api/app/routers/tracks.py` — full replacement:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_tracks_api.py -v`
Expected: PASS (all tests, including the three new ones)

- [ ] **Step 5: Run the full backend suite, including `test_waypoints_api.py`, to confirm the generic router change has no effect on waypoints**

Run: `pytest -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add api/app/routers/resource_crud.py api/app/schemas/tracks.py api/app/services/resources.py api/app/routers/tracks.py api/tests/test_tracks_api.py
git commit -m "feat: compute and expose track length, duration, and elevation gain"
```

---

### Task 5: Flutter `TrackPoint`/`Track` — elevation and measurement fields

**Files:**
- Modify: `app/lib/tracks/track_models.dart`
- Modify: `app/test/tracks/track_models_test.dart`

**Interfaces:**
- Produces: `TrackPoint({required lat, required lng, elevationMeters = 0.0})`;
  `Track` gains `lengthMeters` (double, default `0.0`), `durationSeconds` (`int?`), `elevationGainMeters`
  (`double?`), all parsed in `Track.fromJson`. Consumed by Tasks 6-12.

- [ ] **Step 1: Write the failing test**

Append to `app/test/tracks/track_models_test.dart` (inside the existing `group('Track.fromJson', ...)`, as a
sibling `test(...)` to the existing one):

```dart
    test('parses elevation and measurement fields when present', () {
      final json = {
        'id': 't1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Ridge Loop',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9, 1200.0],
            [7.7, 46.0, 1250.5],
          ],
        },
        'created_at': '2026-08-22T10:00:00Z',
        'length_meters': 4200.5,
        'duration_seconds': 5400,
        'elevation_gain_meters': 320.0,
      };

      final track = Track.fromJson(json);

      expect(track.points[0].elevationMeters, 1200.0);
      expect(track.points[1].elevationMeters, 1250.5);
      expect(track.lengthMeters, 4200.5);
      expect(track.durationSeconds, 5400);
      expect(track.elevationGainMeters, 320.0);
    });

    test('defaults measurement fields when absent', () {
      final json = {
        'id': 't1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Old track',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9],
            [7.7, 46.0],
          ],
        },
        'created_at': '2026-08-20T10:00:00Z',
      };

      final track = Track.fromJson(json);

      expect(track.points[0].elevationMeters, 0.0);
      expect(track.lengthMeters, 0.0);
      expect(track.durationSeconds, isNull);
      expect(track.elevationGainMeters, isNull);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `app/`): `flutter test test/tracks/track_models_test.dart`
Expected: FAIL — `elevationMeters`/`lengthMeters`/`durationSeconds`/`elevationGainMeters` don't exist yet

- [ ] **Step 3: Implement**

Replace `app/lib/tracks/track_models.dart`:

```dart
class TrackPoint {
  const TrackPoint({required this.lat, required this.lng, this.elevationMeters = 0.0});

  final double lat;
  final double lng;
  final double elevationMeters;
}

class Track {
  const Track({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.points,
    required this.createdAt,
    this.lengthMeters = 0.0,
    this.durationSeconds,
    this.elevationGainMeters,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String name;
  final List<TrackPoint> points;
  final DateTime createdAt;
  final double lengthMeters;
  final int? durationSeconds;
  final double? elevationGainMeters;

  factory Track.fromJson(Map<String, dynamic> json) {
    final geom = json['geom'] as Map<String, dynamic>;
    final coordinates = geom['coordinates'] as List<dynamic>;
    return Track(
      id: json['id'] as String,
      orgId: json['org_id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      points: [
        for (final c in coordinates)
          TrackPoint(
            lng: ((c as List<dynamic>)[0] as num).toDouble(),
            lat: (c[1] as num).toDouble(),
            elevationMeters: c.length > 2 ? (c[2] as num).toDouble() : 0.0,
          ),
      ],
      createdAt: DateTime.parse(json['created_at'] as String),
      lengthMeters: (json['length_meters'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      elevationGainMeters: (json['elevation_gain_meters'] as num?)?.toDouble(),
    );
  }
}

class TrackException implements Exception {
  const TrackException(this.message);

  final String message;

  @override
  String toString() => 'TrackException: $message';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tracks/track_models_test.dart`
Expected: PASS (all tests, including the two pre-existing ones — unmodified and still compatible)

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/track_models.dart app/test/tracks/track_models_test.dart
git commit -m "feat: parse track elevation, length, duration, and elevation gain"
```

---

### Task 6: Capture altitude in `GeolocatorLocationSource`

**Files:**
- Modify: `app/lib/tracks/location_source.dart`

**Interfaces:**
- Consumes: `TrackPoint(elevationMeters: ...)` (Task 5).
- Produces: `GeolocatorLocationSource.positionStream`/`getCurrentPosition` now populate `elevationMeters`
  from `Position.altitude`.

- [ ] **Step 1: Implement (no new automated test — `GeolocatorLocationSource` wraps the `geolocator` plugin and has no existing direct unit test; verified manually per Task 13-equivalent device testing, same as its pre-existing lat/lng capture)**

In `app/lib/tracks/location_source.dart`, update the two `TrackPoint(...)` constructions inside
`GeolocatorLocationSource`:

```dart
  @override
  Stream<TrackPoint> positionStream({required int distanceFilterMeters}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(distanceFilter: distanceFilterMeters),
    ).map(
      (position) => TrackPoint(
        lat: position.latitude,
        lng: position.longitude,
        elevationMeters: position.altitude,
      ),
    );
  }

  @override
  Future<TrackPoint?> getCurrentPosition() async {
    final granted = await ensurePermission();
    if (!granted) return null;
    final position = await Geolocator.getCurrentPosition();
    return TrackPoint(lat: position.latitude, lng: position.longitude, elevationMeters: position.altitude);
  }
```

- [ ] **Step 2: Run the existing location_source tests to confirm no regression**

Run: `flutter test test/tracks/location_source_test.dart`
Expected: PASS (these tests exercise `FakeLocationSource`, not `GeolocatorLocationSource`, so they're
unaffected — this step just guards against a typo)

- [ ] **Step 3: Commit**

```bash
git add app/lib/tracks/location_source.dart
git commit -m "feat: capture GPS altitude into recorded track points"
```

---

### Task 7: `TrackRecordingController.stop()` returns start/finish timestamps

**Files:**
- Modify: `app/lib/tracks/track_recording_controller.dart`
- Modify: `app/test/tracks/track_recording_controller_test.dart`

**Interfaces:**
- Produces: new class `TrackRecordingResult { points, startedAt, finishedAt }`;
  `TrackRecordingController.stop()` now returns `TrackRecordingResult?` (was `List<TrackPoint>`) — `null`
  when called while already idle. Consumed by Task 9 (`map_screen.dart`).

- [ ] **Step 1: Update the failing tests**

In `app/test/tracks/track_recording_controller_test.dart`, replace the `group('stop', ...)` block:

```dart
  group('stop', () {
    test('returns the accumulated points and timestamps, and transitions back to idle', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);
      source.emit(const TrackPoint(lat: 1.1, lng: 2.1));
      await Future<void>.delayed(Duration.zero);

      final result = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(result, isNotNull);
      expect(result!.points, hasLength(2));
      expect(result.finishedAt.isAfter(result.startedAt) || result.finishedAt.isAtSameMomentAs(result.startedAt),
          isTrue);
      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });

    test('further emissions after stop are not accumulated', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      container.read(trackRecordingControllerProvider.notifier).stop();

      source.emit(const TrackPoint(lat: 9.0, lng: 9.0));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });

    test('returns null and is a no-op when already idle', () {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      final result = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(result, isNull);
      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/tracks/track_recording_controller_test.dart`
Expected: FAIL — `result.points`/`result.startedAt` don't exist on `List<TrackPoint>`, and `stop()` currently
returns `const []` (not `null`) when idle

- [ ] **Step 3: Implement**

In `app/lib/tracks/track_recording_controller.dart`, add the result class and change `stop()`:

```dart
class TrackRecordingResult {
  const TrackRecordingResult({required this.points, required this.startedAt, required this.finishedAt});

  final List<TrackPoint> points;
  final DateTime startedAt;
  final DateTime finishedAt;
}
```

```dart
  TrackRecordingResult? stop() {
    final current = state;
    _subscription?.cancel();
    _subscription = null;
    state = const TrackRecordingIdle();
    if (current is! TrackRecordingActive) return null;
    return TrackRecordingResult(
      points: current.points,
      startedAt: current.startedAt,
      finishedAt: DateTime.now(),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tracks/track_recording_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/track_recording_controller.dart app/test/tracks/track_recording_controller_test.dart
git commit -m "feat: return start/finish timestamps from TrackRecordingController.stop()"
```

---

### Task 8: Plumb `startedAt`/`finishedAt` through `TracksRepository`/`TracksController`

**Files:**
- Modify: `app/lib/tracks/tracks_repository.dart`
- Modify: `app/lib/tracks/tracks_controller.dart`
- Modify: `app/test/tracks/fakes.dart`
- Modify: `app/test/tracks/tracks_controller_test.dart`

**Interfaces:**
- Consumes: `Track`/`TrackPoint` (Task 5).
- Produces: `TracksRepository.create(...)` and `TracksController.saveTrack(...)` gain optional
  `DateTime? startedAt`, `DateTime? finishedAt` parameters. Consumed by Task 9 (`map_screen.dart`).

- [ ] **Step 1: Update the failing test**

In `app/test/tracks/tracks_controller_test.dart`, replace the `group('saveTrack', ...)` block's first test
to also assert the values reach the repository:

```dart
  group('saveTrack', () {
    test('appends the created track to state and forwards timing to the repository', () async {
      final repo = FakeTracksRepository()..createResult = _track(id: 'server-id');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      final startedAt = DateTime.utc(2026, 9, 13, 8);
      final finishedAt = DateTime.utc(2026, 9, 13, 9, 30);

      await container.read(tracksControllerProvider.notifier).saveTrack(
            name: 'Morning walk',
            points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
            startedAt: startedAt,
            finishedAt: finishedAt,
          );

      final state = container.read(tracksControllerProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'server-id');
      expect(repo.lastCreateStartedAt, startedAt);
      expect(repo.lastCreateFinishedAt, finishedAt);
    });
```

(the second `saveTrack` test, `'leaves state unchanged and rethrows on failure'`, is unchanged)

Also add to `app/test/tracks/fakes.dart`'s `FakeTracksRepository`:

```dart
  DateTime? lastCreateStartedAt;
  DateTime? lastCreateFinishedAt;
```

and record them inside `create(...)` (see Step 3 for the full new signature).

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/tracks/tracks_controller_test.dart`
Expected: FAIL — `saveTrack` doesn't accept `startedAt`/`finishedAt`, and `FakeTracksRepository` has no
`lastCreateStartedAt`/`lastCreateFinishedAt`

- [ ] **Step 3: Implement**

`app/lib/tracks/tracks_repository.dart` — full replacement:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'track_models.dart';

abstract class TracksRepository {
  Future<List<Track>> list(String token);

  Future<Track> create(
    String token, {
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  });
}

class HttpTracksRepository implements TracksRepository {
  HttpTracksRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Track>> list(String token) async {
    final response = await _client.get('/tracks?limit=200', token: token);
    if (response.statusCode != 200) {
      throw const TrackException('Could not load tracks');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Track> create(
    String token, {
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final response = await _client.post(
      '/tracks',
      token: token,
      body: {
        'name': name,
        'geom': {
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lng, p.lat, p.elevationMeters],
          ],
        },
        if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
        if (finishedAt != null) 'finished_at': finishedAt.toUtc().toIso8601String(),
      },
    );
    if (response.statusCode != 201) {
      throw const TrackException('Could not create track');
    }
    return Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
```

`app/lib/tracks/tracks_controller.dart` — change `saveTrack`:

```dart
  Future<void> saveTrack({
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final token = await _storage.read();
    if (token == null) return;
    final created = await _repository.create(
      token,
      name: name,
      points: points,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
    state = [...state, created];
  }
```

`app/test/tracks/fakes.dart` — full replacement:

```dart
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_repository.dart';

class FakeTracksRepository implements TracksRepository {
  FakeTracksRepository({List<Track>? initial}) : items = List.of(initial ?? const []);

  final List<Track> items;

  /// Set to a Track for success, or a TrackException instance to throw.
  Object? createResult;

  DateTime? lastCreateStartedAt;
  DateTime? lastCreateFinishedAt;

  @override
  Future<List<Track>> list(String token) async => List.of(items);

  @override
  Future<Track> create(
    String token, {
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    lastCreateStartedAt = startedAt;
    lastCreateFinishedAt = finishedAt;
    if (createResult is TrackException) throw createResult as TrackException;
    return createResult as Track;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tracks/tracks_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full Flutter test suite to catch any other `FakeTracksRepository`/`TracksRepository` consumer**

Run: `flutter test`
Expected: PASS (this will also catch `map_screen_test.dart`, which is fixed in the next task if it fails
here due to the `TracksRepository` interface change — if it fails now, that's expected and resolved by
Task 9)

- [ ] **Step 6: Commit**

```bash
git add app/lib/tracks/tracks_repository.dart app/lib/tracks/tracks_controller.dart app/test/tracks/fakes.dart app/test/tracks/tracks_controller_test.dart
git commit -m "feat: forward recording start/finish timestamps when saving a track"
```

---

### Task 9: Wire `MapScreen`'s record flow to the new `stop()`/`saveTrack()` signatures + add a "Треки" entry icon

**Files:**
- Modify: `app/lib/map/map_screen.dart`
- Modify: `app/test/map/map_screen_test.dart` (only if Task 8's full-suite run showed a failure here)

**Interfaces:**
- Consumes: `TrackRecordingController.stop() -> TrackRecordingResult?` (Task 7),
  `TracksController.saveTrack(..., startedAt, finishedAt)` (Task 8), `TracksListScreen` (Task 11).
- Produces: a new AppBar `IconButton` (key `tracks_list_button`) that pushes `TracksListScreen`.

- [ ] **Step 1: Update `_onRecordToggle`**

In `app/lib/map/map_screen.dart`, replace the body of `_onRecordToggle`:

```dart
  Future<void> _onRecordToggle(TrackRecordingState recordingState) async {
    if (recordingState is TrackRecordingActive) {
      final stopResult = ref.read(trackRecordingControllerProvider.notifier).stop();
      if (stopResult == null || stopResult.points.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Трек слишком короткий, чтобы сохранить')),
          );
        }
        return;
      }
      final result = await showTrackNameFormSheet(context, initialName: _defaultTrackName());
      if (result == null || !mounted) return;
      try {
        await ref.read(tracksControllerProvider.notifier).saveTrack(
              name: result.name,
              points: stopResult.points,
              startedAt: stopResult.startedAt,
              finishedAt: stopResult.finishedAt,
            );
      } on TrackException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } else {
      await ref.read(trackRecordingControllerProvider.notifier).start();
      final newState = ref.read(trackRecordingControllerProvider);
      if (newState is TrackRecordingIdle && newState.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newState.errorMessage!)));
      }
    }
  }
```

- [ ] **Step 2: Add the AppBar entry icon**

Add the import (alongside the other `tracks/` imports near the top of the file):

```dart
import '../tracks/tracks_list_screen.dart';
```

In the `build` method's `AppBar.actions`, add a new `IconButton` between the existing `layers_button` and
`logout` buttons:

```dart
          IconButton(
            key: const Key('tracks_list_button'),
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TracksListScreen()),
            ),
          ),
```

(This references `TracksListScreen`, created in Task 11 — this task will not compile/pass its widget test
until Task 11 lands. That's expected: Tasks 9-12 are a tightly coupled UI slice, run and committed together
per the "batch execution with checkpoints" note if using inline execution, or reviewed as a connected
sequence if using subagent-driven execution.)

- [ ] **Step 3: Run the full Flutter test suite**

Run: `flutter test`
Expected: FAIL only on anything referencing `TracksListScreen` (not yet created) — proceed to Tasks 10-11,
then return here to confirm PASS. If `map_screen_test.dart`'s existing tests reference
`FakeTracksRepository.create` positionally in a way Task 8 broke, fix those call sites now (they use only
named `name:`/`points:` args per the file read during planning, so no changes are expected here).

- [ ] **Step 4: Commit** (after Task 11 makes this compile — see that task's commit step, which includes
  this file)

---

### Task 10: `format_track_stats.dart` — shared formatting helpers

**Files:**
- Create: `app/lib/tracks/format_track_stats.dart`
- Create: `app/test/tracks/format_track_stats_test.dart`

**Interfaces:**
- Produces: `formatTrackLength(double meters) -> String`, `formatTrackDuration(int? seconds) -> String`,
  `formatElevationGain(double? meters) -> String`, `formatTrackDate(DateTime dateTime) -> String`. Consumed
  by Tasks 11 and 12.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/tracks/format_track_stats_test.dart
import 'package:app/tracks/format_track_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTrackLength', () {
    test('shows meters under 1 km', () {
      expect(formatTrackLength(850), '850 м');
    });

    test('shows kilometers with one decimal at or above 1 km', () {
      expect(formatTrackLength(4200), '4.2 км');
    });
  });

  group('formatTrackDuration', () {
    test('shows dash when null', () {
      expect(formatTrackDuration(null), '—');
    });

    test('shows minutes only under an hour', () {
      expect(formatTrackDuration(25 * 60), '25 мин');
    });

    test('shows hours and minutes at or above an hour', () {
      expect(formatTrackDuration(85 * 60), '1 ч 25 мин');
    });
  });

  group('formatElevationGain', () {
    test('shows dash when null', () {
      expect(formatElevationGain(null), '—');
    });

    test('shows a rounded value with a plus sign', () {
      expect(formatElevationGain(320.4), '+320 м');
    });
  });

  group('formatTrackDate', () {
    test('formats as dd.mm.yyyy in local time', () {
      final date = DateTime(2026, 9, 13, 10, 0);
      expect(formatTrackDate(date), '13.09.2026');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/tracks/format_track_stats_test.dart`
Expected: FAIL with a compile error (`format_track_stats.dart` doesn't exist)

- [ ] **Step 3: Implement**

```dart
// app/lib/tracks/format_track_stats.dart

String formatTrackLength(double meters) {
  if (meters < 1000) {
    return '${meters.round()} м';
  }
  final km = meters / 1000;
  return '${km.toStringAsFixed(1)} км';
}

String formatTrackDuration(int? seconds) {
  if (seconds == null) return '—';
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours ч $minutes мин';
  }
  return '$minutes мин';
}

String formatElevationGain(double? meters) {
  if (meters == null) return '—';
  return '+${meters.round()} м';
}

String formatTrackDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tracks/format_track_stats_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/format_track_stats.dart app/test/tracks/format_track_stats_test.dart
git commit -m "feat: add track length/duration/elevation formatting helpers"
```

---

### Task 11: `TracksListScreen`

**Files:**
- Create: `app/lib/tracks/tracks_list_screen.dart`
- Create: `app/test/tracks/tracks_list_screen_test.dart`

**Interfaces:**
- Consumes: `tracksControllerProvider`/`tracksRepositoryProvider` (existing), `tokenStorageProvider`
  (existing), `formatTrackLength`/`formatTrackDuration`/`formatTrackDate` (Task 10),
  `TrackDetailScreen` (Task 12, referenced but not yet created — see Step 3 note).
- Produces: `TracksListScreen` widget, pushed from `MapScreen` (Task 9).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/tracks/tracks_list_screen_test.dart
import 'package:app/auth/token_storage.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/tracks/tracks_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Track _track({String id = 't1', String name = 'Morning walk'}) {
  return Track(
    id: id,
    orgId: 'o1',
    ownerId: 'u1',
    name: name,
    points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
    createdAt: DateTime.utc(2026, 9, 13),
    lengthMeters: 4200,
    durationSeconds: 5400,
    elevationGainMeters: 320,
  );
}

void main() {
  testWidgets('shows an empty message when there are no tracks', (tester) async {
    final tokenStorage = FakeTokenStorage()..write('tok-1');
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
        tokenStorageProvider.overrideWithValue(tokenStorage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Пока нет сохранённых треков'), findsOneWidget);
  });

  testWidgets('lists tracks with formatted length and duration', (tester) async {
    final tokenStorage = FakeTokenStorage()..write('tok-1');
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository(initial: [_track()])),
        tokenStorageProvider.overrideWithValue(tokenStorage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.textContaining('4.2 км'), findsOneWidget);
    expect(find.textContaining('1 ч 25 мин'), findsOneWidget);
  });

  testWidgets('tapping a track card navigates to its detail screen', (tester) async {
    final tokenStorage = FakeTokenStorage()..write('tok-1');
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository(initial: [_track()])),
        tokenStorageProvider.overrideWithValue(tokenStorage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning walk'));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет сохранённых треков'), findsNothing);
    expect(find.byKey(const Key('track_stats_row')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/tracks/tracks_list_screen_test.dart`
Expected: FAIL with a compile error (`tracks_list_screen.dart` doesn't exist)

- [ ] **Step 3: Implement**

```dart
// app/lib/tracks/tracks_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format_track_stats.dart';
import 'track_detail_screen.dart';
import 'tracks_controller.dart';

class TracksListScreen extends ConsumerStatefulWidget {
  const TracksListScreen({super.key});

  @override
  ConsumerState<TracksListScreen> createState() => _TracksListScreenState();
}

class _TracksListScreenState extends ConsumerState<TracksListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(tracksControllerProvider.notifier).loadTracks());
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Треки')),
      body: tracks.isEmpty
          ? const Center(child: Text('Пока нет сохранённых треков'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    key: Key('track_card_${track.id}'),
                    title: Text(track.name, style: const TextStyle(fontSize: 18)),
                    subtitle: Text(
                      '${formatTrackDate(track.createdAt)} · ${formatTrackLength(track.lengthMeters)} · '
                      '${formatTrackDuration(track.durationSeconds)}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TrackDetailScreen(track: track)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
```

This references `TrackDetailScreen`, created in Task 12. `tracks_list_screen_test.dart`'s third test
(tapping navigates) will not pass until Task 12 lands — that's expected for this tightly-coupled pair.

- [ ] **Step 4: Implement Task 12 now (see next task), then return and run**

Run: `flutter test test/tracks/tracks_list_screen_test.dart`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit** (bundled with Task 12's files, see that task's commit step)

---

### Task 12: `TrackDetailScreen`

**Files:**
- Create: `app/lib/tracks/track_detail_screen.dart`
- Create: `app/test/tracks/track_detail_screen_test.dart`

**Interfaces:**
- Consumes: `Track` (Task 5), `formatTrackLength`/`formatTrackDuration`/`formatElevationGain` (Task 10),
  `AppConfig.mapStyleUrl` (existing, `app/lib/config.dart`).
- Produces: `TrackDetailScreen({required Track track})` widget, referenced by Task 11.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/tracks/track_detail_screen_test.dart
import 'package:app/tracks/track_detail_screen.dart';
import 'package:app/tracks/track_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track({int? durationSeconds, double? elevationGainMeters}) {
  return Track(
    id: 't1',
    orgId: 'o1',
    ownerId: 'u1',
    name: 'Ridge Loop',
    points: const [TrackPoint(lat: 45.9, lng: 7.6), TrackPoint(lat: 46.0, lng: 7.7)],
    createdAt: DateTime.utc(2026, 9, 13),
    lengthMeters: 4200,
    durationSeconds: durationSeconds,
    elevationGainMeters: elevationGainMeters,
  );
}

void main() {
  testWidgets('shows the track name and formatted stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TrackDetailScreen(track: _track(durationSeconds: 5400, elevationGainMeters: 320))),
    );
    await tester.pump();

    expect(find.text('Ridge Loop'), findsOneWidget);
    expect(find.textContaining('4.2 км'), findsOneWidget);
    expect(find.textContaining('1 ч 25 мин'), findsOneWidget);
    expect(find.textContaining('+320 м'), findsOneWidget);
  });

  testWidgets('shows a dash for null duration and elevation gain', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrackDetailScreen(track: _track())));
    await tester.pump();

    expect(find.text('—'), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/tracks/track_detail_screen_test.dart`
Expected: FAIL with a compile error (`track_detail_screen.dart` doesn't exist)

- [ ] **Step 3: Implement**

```dart
// app/lib/tracks/track_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import 'format_track_stats.dart';
import 'track_models.dart';

class TrackDetailScreen extends StatefulWidget {
  const TrackDetailScreen({super.key, required this.track});

  final Track track;

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  MapLibreMapController? _controller;

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    final points = widget.track.points;
    if (controller == null || points.isEmpty) return;

    await controller.addLine(
      LineOptions(
        geometry: [for (final p in points) LatLng(p.lat, p.lng)],
        lineColor: '#1976D2',
        lineWidth: 3,
      ),
    );

    if (points.length < 2) return;
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        left: 32,
        top: 32,
        right: 32,
        bottom: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final firstPoint = track.points.isEmpty ? null : track.points.first;
    return Scaffold(
      appBar: AppBar(title: Text(track.name)),
      body: Column(
        children: [
          Expanded(
            child: MapLibreMap(
              styleString: AppConfig.mapStyleUrl,
              initialCameraPosition: CameraPosition(
                target: firstPoint == null ? const LatLng(0, 0) : LatLng(firstPoint.lat, firstPoint.lng),
                zoom: 12,
              ),
              onMapCreated: (controller) => _controller = controller,
              onStyleLoadedCallback: _onStyleLoaded,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              key: const Key('track_stats_row'),
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Длина', value: formatTrackLength(track.lengthMeters)),
                _Stat(label: 'Время', value: formatTrackDuration(track.durationSeconds)),
                _Stat(label: 'Набор высоты', value: formatElevationGain(track.elevationGainMeters)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tracks/track_detail_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Now return to Task 11's Step 4 and Task 9's Step 3**

Run: `flutter test`
Expected: PASS across the whole suite (`tracks_list_screen_test.dart`'s navigation test and
`map_screen_test.dart` now compile against the completed `TracksListScreen`/`TrackDetailScreen`/updated
`TracksRepository` interface)

- [ ] **Step 6: Commit everything from Tasks 9, 11, and 12 together**

```bash
git add app/lib/map/map_screen.dart app/lib/tracks/tracks_list_screen.dart app/lib/tracks/track_detail_screen.dart app/test/tracks/tracks_list_screen_test.dart app/test/tracks/track_detail_screen_test.dart
git commit -m "feat: add track list and detail screens with length/duration/elevation stats"
```

---

### Task 13: Manual device verification

**Files:** none (manual QA pass, per the existing convention in `2026-08-22-track-recording-slice-design.md`
and `2026-08-22-waypoints-map-slice-design.md` — no working Android emulator on the dev machine)

- [ ] **Step 1: Record a real track on-device** covering a genuine elevation change (a hill, a staircase, a
  multi-floor building), confirm the "Треки" list shows it with a plausible length and duration.

- [ ] **Step 2: Open its detail screen**, confirm the mini-map renders the track fit to its bounds, and that
  the elevation gain roughly matches the real terrain (not wildly inflated by GPS noise).

- [ ] **Step 3: Record a very short track** (under 2 points) and confirm the existing "Трек слишком
  короткий" snackbar still fires (regression check on Task 9's change).

- [ ] **Step 4: Confirm the migration ran cleanly against whatever shared/staging database exists** (if any,
  beyond the Task 3 Step 4 scratch-DB check) before this ships anywhere besides local dev.
