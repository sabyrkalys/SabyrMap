# Track view & measurement — design

Date: 2026-09-13
Status: approved for planning

## Context

The track-recording slice (`2026-08-22-track-recording-slice-design.md`) explicitly deferred track
statistics and any way to view a saved track other than as a polyline on the map layers toggle.
This spec covers that next slice: a dedicated screen listing saved tracks with length/duration, a
detail screen showing one track's measurements (length, duration, elevation gain) plus a read-only
mini-map, and the backend/data changes needed to support those measurements.

This design is independently authored for this project's own architecture (Flutter + MapLibre +
FastAPI/PostGIS), not derived from or copied from any third-party application's implementation —
see `project_two_release_track_plan` memory for why that boundary matters here.

## Explicitly out of scope for this slice

- Renaming or deleting a track from the detail screen — read-only view only. A track-management
  slice can add this later, reusing the existing `PATCH`/`DELETE /tracks/{id}` endpoints.
- Elevation profile chart, speed, pace — only total length, total duration, and total elevation
  gain are shown.
- Backfilling `started_at`/`finished_at`/elevation for tracks recorded before this slice ships —
  those columns are nullable; pre-existing tracks show duration/elevation gain as unavailable
  (`—`) in the UI, and their `geom` is upgraded to 3D via `ST_Force3D` (z=0) by the migration so the
  column type change doesn't fail on existing rows.
- Tap-to-select a track directly on the main map's polyline (hit-testing MapLibre lines) — the
  dedicated "Треки" list screen is the only entry point to detail/measurements in this slice.

## Data model & migration

- `tracks.geom`: `LINESTRING` → `LINESTRING Z` (coordinates become `(lon, lat, elevation)`).
  Migration: `ALTER COLUMN geom TYPE geometry(LINESTRINGZ, 4326) USING ST_Force3D(geom)`.
- `tracks` gains two nullable columns: `started_at TIMESTAMPTZ`, `finished_at TIMESTAMPTZ`.
  Nullable (not backfilled) per the out-of-scope note above.

## Backend changes

### `GeoJSONLineString` (`app/schemas/geometry.py`)

- `coordinates: list[tuple[float, float]]` → `list[tuple[float, float, float]]` (lon, lat, elev).
  `linestring_to_geojson`/`geojson_to_linestring` pass the third coordinate through via
  shapely's native 3-tuple `LineString` support — no other change needed in those two functions.

### `TrackCreateRequest` / `TrackUpdateRequest` (`app/schemas/tracks.py`)

- Add `started_at: datetime | None = None`, `finished_at: datetime | None = None`.

### `TrackResponse` (`app/schemas/tracks.py`)

- Add computed, not-stored fields: `length_meters: float`, `duration_seconds: int | None`,
  `elevation_gain_meters: float | None`.
- New module `app/services/track_measurements.py`:
  - `compute_length_meters(coords: list[tuple[float, float, float]]) -> float`: sum of haversine
    great-circle distances between consecutive `(lon, lat)` pairs (ignores elevation — this is
    ground/hiking distance, not slope distance).
  - `compute_elevation_gain_meters(coords) -> float`: sum of positive deltas between consecutive
    elevation values, but only counting a delta once accumulated vertical movement since the last
    counted gain exceeds a 3-meter threshold (a simple running-threshold smoother: track a
    `baseline` elevation, only add `current - baseline` and reset `baseline = current` once
    `current - baseline > 3`; ignore drops). This absorbs GPS altitude noise (±10-20m) without
    external dependencies.
  - Both are pure functions over coordinate lists — unit-testable without a DB or FastAPI app.

### `build_resource_router` (`app/routers/resource_crud.py`)

- New optional parameter `extra_response_fields: Callable[[Any], dict] | None = None` (default
  `None`, so `waypoints.py`'s call site is untouched). When provided, `_to_response` merges
  `extra_response_fields(entity)` into the `response_schema(...)` kwargs.
- `tracks.py` passes an `extra_response_fields` that shapes the entity's `geom` to coordinates
  once (via `to_shape`) and returns `length_meters`/`elevation_gain_meters` from
  `track_measurements`, plus `duration_seconds` computed from `entity.started_at`/`finished_at`
  (`None` if either is `None`).

## Frontend changes

### `TrackPoint` / `Track` (`track_models.dart`)

- `TrackPoint` gains `elevationMeters` (from `Position.altitude` in `location_source.dart`'s
  stream mapping — Geolocator always reports a value, even if low-accuracy).
- `Track` gains `lengthMeters`, `durationSeconds` (nullable), `elevationGainMeters` (nullable),
  parsed from the new response fields. `fromJson`'s coordinate parsing reads a 3-element
  `[lon, lat, elev]` array instead of 2.

### `TrackRecordingController`

- `TrackRecordingActive` already carries `startedAt`. `stop()` changes its return type from
  `List<TrackPoint>` to a small record `(points: List<TrackPoint>, startedAt: DateTime, finishedAt: DateTime)`
  (finishedAt = `DateTime.now()` at the moment `stop()` runs).

### `TracksController` / `TracksRepository`

- `saveTrack` and `HttpTracksRepository.create` gain `startedAt`/`finishedAt` parameters, sent as
  `started_at`/`finished_at` in the `POST /tracks` body.

### New `tracks` list & detail screens

- **`TracksListScreen`**: pushed from a new AppBar icon on `MapScreen` (alongside the existing
  layers/record icons). Loads via `TracksController.loadTracks()` if not already loaded. Renders
  each `Track` as a card: name, formatted date, length (`"4.2 км"`, or meters below 1 km),
  duration (`"1 ч 25 мин"`, or `"—"` if `null`). Tapping a card pushes `TrackDetailScreen(track)`.
- **`TrackDetailScreen`**: read-only. A small non-interactive MapLibre view showing the track's
  polyline fit to its bounds (reuses the same `Line`-drawing approach as `MapScreen`, without GPS
  or editing), plus three stat rows: length, duration, elevation gain (`"+320 м"`, or `"—"` if
  `null`).
- A small `format_track_stats.dart` (or similarly named) pure-function module holds the km/h:mm
  formatting shared by both screens, unit-tested directly.

## Testing

- `track_measurements.py`: unit tests for `compute_length_meters` (known coordinate pairs against
  a hand-computed haversine distance) and `compute_elevation_gain_meters` (monotonic climb, noisy
  jitter below threshold contributes nothing, a climb-then-drop-then-climb-past-threshold pattern).
- API test extending `test_tracks_api.py`: `POST /tracks` with 3D coordinates and
  `started_at`/`finished_at` round-trips `length_meters`/`duration_seconds`/`elevation_gain_meters`
  in the response; a track created without `started_at`/`finished_at` returns
  `duration_seconds: null`.
- Migration test per the existing `project_migration_test_gap` caution: verify the migration
  directly (apply it against a throwaway DB and assert the column type and a forced-3D existing
  row), not just via `metadata.create_all`-backed app tests.
- Flutter: unit tests for `Track.fromJson` parsing the new fields, `TrackRecordingController`
  returning `finishedAt`, and the stat-formatting functions. Widget tests for `TracksListScreen`
  (card content, tap navigation) and `TrackDetailScreen` (stat rows render, `—` shown for null
  fields), following the existing fake-repository pattern from `tracks_controller_test.dart`.
- Manual device verification (no working Android emulator on the dev machine, per prior slices):
  a real recorded track's elevation gain looks sane against a known trail, list/detail screens
  render correctly on-device.
