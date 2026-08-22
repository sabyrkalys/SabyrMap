# Waypoints on the map — design

Date: 2026-08-22
Status: approved for planning

## Context

Roadmap weeks 3–4 ("Метки и треки на карте") bundle waypoints, tracks, and distance/azimuth
measurement. That is too large for one implementation slice. This spec covers the first
sub-slice: **waypoints only** — placing, viewing, editing, and deleting point markers on the
map, backed by the existing `waypoints` resource CRUD API.

Backend resource CRUD/sharing (`POST/GET/PATCH/DELETE /waypoints[/{id}]`,
`can_view_resource`/`can_edit_resource`) is already implemented and merged (see
`docs/superpowers/specs/2026-08-15-resource-crud-design.md`). Frontend currently has only auth
screens and an empty `MapLibreMap` (`app/lib/map/map_screen.dart`) — no markers, no
create/edit/delete UI, no `PATCH`/`DELETE` support in `ApiClient`.

## Explicitly out of scope for this slice

- Tracks (line geometries) and distance/azimuth measurement tools — later slices.
- Full offline queueing (local DB, sync-on-reconnect, conflict resolution) — roadmap week 10.
  This slice's "optimistic UI" only covers the current online session: if the network request
  fails, the optimistic change is rolled back and an error is shown. Nothing is persisted
  locally to retry later.
- Real-time updates from other users (roadmap weeks 5–6) — this slice loads waypoints once per
  screen open; no polling/websocket push.
- Custom/uploadable icons — see [[project_waypoint_icon_type_design]] memory. `type` is a plain
  string column specifically so a future "waypoint types" registry with uploadable icons (open
  to all roles, not admin-only) can be added later without a breaking migration. For now, icons
  are a hardcoded client-side map from a fixed base type list.
- Share-management UI (creating/revoking `resource_shares` from the app) — the list endpoint
  already returns shared-with-me waypoints (`can_view_resource` filter), so viewing shared
  waypoints works, but managing who a waypoint is shared with is a separate future slice.

## Backend changes

### Migration

Add to `waypoints`:
- `type: String`, `NOT NULL`, server default `'generic'`.
- `note: String(500)`, nullable.

Plain string, not a Postgres enum — the app's known type list (`generic/camp/water/danger/point`)
is enforced client-side only, so adding new types later doesn't require a migration.

### Schemas (`app/schemas/waypoints.py`)

- `WaypointCreateRequest`: add `type: str = Field(min_length=1)`, `note: str | None = Field(default=None, max_length=500)`.
- `WaypointUpdateRequest`: add `type: str | None = Field(default=None, min_length=1)`, `note: str | None = Field(default=None, max_length=500)` (same partial-PATCH semantics as `name`/`geom` — omitting the field, or sending `null`, leaves it unchanged; sending an empty string `""` clears it).
- `WaypointResponse`: add `type: str`, `note: str | None`, and **`can_edit: bool`** — computed server-side via the existing `can_edit_resource(db, current_user, resource)`, so the client never re-implements permission logic.

### Router

`waypoints` currently shares `build_resource_router()` with `tracks`. Since `type`/`note`/`can_edit`
are waypoint-specific (tracks aren't in scope here), the implementer should either:
(a) extend `build_resource_router` with optional entity-specific response-field hooks, or
(b) give `waypoints` its own thin router built on the same query/permission helpers.
Either is acceptable — decide during implementation; it's an internal detail, not an API change.

### Tests

Extend the existing waypoint CRUD test suite to cover `type`/`note`/`can_edit` across
create/get/list/update, including: `can_edit=true` for the owner, `can_edit=true` for a
user with an EDIT-scope share, `can_edit=false` for a VIEW-scope share.

## Frontend changes

### API layer

- `ApiClient` (`app/lib/api/api_client.dart`): add `patch()` and `delete()` methods (currently only `get`/`post`).
- New `Waypoint` model: `id, orgId, ownerId, name, type, note, lat, lng, canEdit, createdAt`.
- New `WaypointsRepository` wrapping `ApiClient` calls for `GET/POST/PATCH/DELETE /waypoints`.
- New `WaypointsController` (Riverpod `Notifier`, mirroring `AuthController`'s shape): holds the
  in-memory list of loaded waypoints; exposes `loadWaypoints()`, `createWaypoint()`,
  `updateWaypoint()`, `deleteWaypoint()`. Create/update/delete apply an optimistic local change
  first, then await the network call; on failure, roll back the local change and surface an
  error (e.g., `SnackBar`).

### Map interaction (`MapScreen`)

- On screen open, `WaypointsController.loadWaypoints()` (own + shared-with-me, per the existing
  `GET /waypoints` `can_view_resource` filter — org-scoped, already correct server-side).
- Render each waypoint as a symbol/marker via `maplibre_gl`'s symbol layer. Icon chosen from a
  hardcoded `Map<String, IconData>` keyed by `type`, falling back to the `generic` icon for an
  unrecognized type string. Own vs. shared-with-me waypoints get a visually distinct marker
  (e.g., different marker color/tint) so the difference is visible directly on the map.
- Long-press on the map opens a bottom sheet "New waypoint" form: `name` (required), `type`
  (choice among the 5 base icons), `note` (optional, ≤500 chars). Submitting creates the
  waypoint optimistically at the long-press coordinates, then fires `POST /waypoints` in the
  background.
- Tapping an existing marker opens a bottom sheet showing `name`/`type`/`note` (read-only).
  "Edit" and "Delete" buttons are shown only when `canEdit == true` on that waypoint.
  - Edit reopens the same form, pre-filled, submitting via `PATCH` instead of `POST`.
  - Delete asks for confirmation, then fires `DELETE`, removing the marker optimistically.

## Testing

- Backend: extend `api/tests` for the new fields/`can_edit` cases listed above.
- Frontend: `flutter test` coverage for `WaypointsController` (create/update/delete, and the
  rollback-on-network-failure path) against a mocked `ApiClient`, plus a widget test for the
  create/edit bottom sheet form. Marker rendering itself (`maplibre_gl` symbol layers) isn't
  unit-testable — manual verification on a real device is required before merge, per this
  project's established practice (see [[project_flutter_auth_map]] memory: no emulator on this
  machine).
