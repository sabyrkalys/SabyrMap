# Track recording — design

Date: 2026-08-22
Status: approved for planning

## Context

Roadmap weeks 3–4 bundle waypoints, tracks, and distance/azimuth measurement into one item.
Waypoints (place/view/edit/delete point markers) are already done. This spec covers the next
sub-slice: **track recording only** — starting/stopping a GPS recording, saving it, and toggling
visibility of saved tracks on the map. Backtrack (retrace-to-start) and track statistics
(distance/time/elevation/speed) are explicitly deferred to later slices built on top of this one.

This design is independently authored for this project's own architecture (Flutter + MapLibre +
FastAPI/PostGIS), not derived from or copied from any third-party application's implementation —
see `project_two_release_track_plan` memory for why that boundary matters here.

## Explicitly out of scope for this slice

- Backtrack (retracing a recorded path back to its start) — later slice.
- Track statistics (distance, duration, elevation gain, speed, elevation chart) — later slice.
  Consequence: recorded points carry only `lat`/`lng`, no elevation or per-point timestamp, since
  nothing in this slice consumes them and the existing `GeoJSONLineString` schema doesn't carry
  them either. A stats slice will need to decide how to capture that (either a schema extension or
  computing from a differently-shaped local buffer) — not decided here.
- Background recording (continuing to record with the screen off or the app backgrounded) — needs
  a foreground service, `ACCESS_BACKGROUND_LOCATION`, and battery-optimization handling. Deferred;
  recording in this slice only runs while `MapScreen` is the active, visible screen.
- Local on-device durability during recording (e.g. persisting points to disk as they're
  captured) — the roadmap already places "Синхронизация и устойчивость" as week 10. If the app is
  killed mid-recording, the in-progress track is lost; nothing has been uploaded yet.
- Periodic/incremental upload during recording — the whole track uploads once, as a single
  `POST /tracks`, when the user taps Stop and confirms the save form.
- Editing/deleting a saved track from the map (view + visibility toggle only in this slice;
  waypoints already have full CRUD UI as a reference for a future track-management slice).
- Track detail sheet (viewing a saved track's name/info by tapping it) — this slice only renders
  tracks as polylines; interaction is deferred alongside stats/backtrack.

## Backend changes

None. `Track` resource CRUD (`POST/GET/PATCH/DELETE /tracks[/{id}]`) already exists, already
requires ≥2 coordinates for the `LineString` geometry (`GeoJSONLineString`'s existing validator),
and already applies the same `can_view_resource`/`can_edit_resource` sharing rules as waypoints.
This slice is pure frontend.

## Frontend changes

### New dependency

Add `geolocator` (Flutter package) for a continuous GPS position stream with distance-based
filtering and built-in permission request handling. Android manifest needs
`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (foreground only — no
`ACCESS_BACKGROUND_LOCATION`, matching the foreground-only scope decision above).

### `tracks` module (mirrors the `waypoints` module's shape)

- `Track` model: `id, orgId, ownerId, name, points (List<LatLng>), createdAt`. No `canEdit` field
  needed yet since this slice has no edit/delete UI for saved tracks — the backend response
  carries it already (matching waypoints' response shape via the same `build_resource_router`),
  the model just doesn't need to expose it until a future slice needs it.
- `TracksRepository` (abstract) + `HttpTracksRepository`: only `list(token) -> Future<List<Track>>`
  is needed for this slice (loading saved tracks when visibility is toggled on) plus
  `create(token, {required name, required points}) -> Future<Track>` (used once, at Stop). No
  `update`/`delete`/`get` methods — not exercised by any UI in this slice, so not built (YAGNI;
  add them when the track-management slice needs them, mirroring how waypoints' repository grew
  its full method set only once each was UI-driven).
- `TracksController` (Riverpod `Notifier<List<Track>>`): `loadTracks()` (mirrors
  `WaypointsController.loadWaypoints()` — same silent-no-op-without-token,
  silent-swallow-on-failure behavior) and `saveTrack({required name, required points})` (calls
  `create`, appends the result to state on success, rethrows `WaypointException`-equivalent
  `TrackException` on failure so the caller can show a `SnackBar`; no optimistic insert needed
  here since the track doesn't exist as a map object until the server confirms it — unlike
  waypoints, there's no "immediately visible marker" expectation for a just-recorded track before
  Stop is even pressed).

### `TrackRecordingController` (new, local-only state — not part of the `tracks` module's
server-backed data)

- `Notifier<TrackRecordingState>` where `TrackRecordingState` is a sealed class:
  `TrackRecordingIdle` | `TrackRecordingActive(points: List<LatLng>, startedAt: DateTime)`.
- `start()`: requests location permission via `geolocator` if not already granted; if denied,
  surfaces an error (no recording starts). On success, subscribes to
  `Geolocator.getPositionStream(locationSettings: LocationSettings(distanceFilter: 10))`, appends
  each position to `points`, transitions to `TrackRecordingActive`.
- `stop()`: cancels the position stream subscription, returns the accumulated points to the
  caller (the caller — `MapScreen` — then shows the name form and, on confirmation, calls
  `TracksController.saveTrack`), and transitions back to `TrackRecordingIdle`. `stop()` does NOT
  itself call the repository — separating "stop capturing" from "save what was captured" keeps
  the controller a pure capture state machine, and lets `MapScreen` show the name form (and
  potentially let the user discard instead of save) without the controller needing to know about
  forms or navigation.
- If `start()` is called while already `TrackRecordingActive`, or `stop()` while
  `TrackRecordingIdle`, both are no-ops (defensive, since the UI's own start/stop button state
  should already prevent this).

### `MapScreen` changes

- Two new `AppBar` actions, alongside the existing logout icon:
  - **Record toggle**: shows a "start recording" icon when `TrackRecordingController` state is
    idle, a "stop recording" icon when active. Tapping while idle calls `start()`. Tapping while
    active calls `stop()`, then shows a bottom-sheet form (mirroring `WaypointFormSheet`'s
    shape): a single required `name` field, pre-filled with
    `'Track ${formatted current date/time}'`, and a Save button. Submitting calls
    `TracksController.saveTrack(name: ..., points: ...)`; a `TrackException` on failure shows a
    `SnackBar` (the points are already gone from `TrackRecordingController`'s state at this point
    — a failed save is not retried automatically, matching this slice's "no local durability"
    scope decision above; the user would need to re-record).
  - **Layers icon**: opens a small bottom sheet with one `Switch`: "Показывать треки" (default
    `false`). Toggling it on calls `TracksController.loadTracks()` if the list is still empty and
    triggers rendering; toggling off just stops rendering (state already loaded stays cached in
    `TracksController`, no need to re-fetch next time it's toggled back on within the same screen
    session).
- **Live recording line**: while `TrackRecordingActive`, a single `maplibre_gl` `Line` (via
  `addLine`/`updateLine`, same lifecycle-guarded/serialized pattern already established for
  waypoint circles in `map_screen.dart` — the circleManager-readiness guard, clearing on style
  reload, and the `_isSyncing`/pending-coalescing scheme apply equally to a `lineManager`) is kept
  in sync with `TrackRecordingController`'s accumulating points, redrawn as new points arrive.
- **Saved tracks**: when the layers toggle is on, each `Track` in `TracksController`'s state is
  rendered as its own `Line`, added/removed following the same sync pattern as circles/the live
  recording line, but keyed by `track.id` (mirrors `_circlesByWaypointId`). Rendered in a distinct
  `lineColor` from the live recording line so a user can tell "currently recording" apart from
  "previously saved."

## Testing

- `TrackRecordingController`: unit tests using a fake position stream (a `Stream<Position>`
  the test controls) — start/stop transitions, points accumulate in order, permission-denied
  path leaves state `TrackRecordingIdle` with an error surfaced.
- `TracksRepository`/`TracksController`: unit tests mirroring the equivalent `waypoints` tests
  exactly in structure (mocked `ApiClient`/fake repository), covering `list`/`create`
  success and failure paths.
- Widget test for the track-name form bottom sheet, mirroring `waypoint_form_sheet_test.dart`'s
  structure (save disabled until non-empty name, pre-filled default value, dismiss returns null).
- `MapScreen` additions: widget tests for the record-toggle icon's state switching and the
  layers-toggle bottom sheet's switch, following the existing `map_screen_test.dart` pattern of
  overriding repositories with fakes and exercising controller calls directly (rather than
  simulating real map gestures, which `flutter test` cannot drive against `maplibre_gl`'s
  platform view — same constraint noted in the waypoints slice).
- Manual device verification (required, same constraint as the waypoints slice — no working
  Android emulator on the dev machine): actual GPS position updates, live line rendering during a
  real walk/drive, permission prompt behavior, and the layers toggle showing/hiding previously
  saved tracks.
