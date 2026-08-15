# Resource CRUD (Waypoints, Tracks, Sharing) — Design

Date: 2026-08-15
Status: Approved, pending implementation plan

## Context

AlpineQuest has a working data model and service layer for map resources
([Roles and Resource Sharing design](2026-08-12-roles-and-sharing-design.md)):
`Resource`/`Waypoint`/`Track`/`ResourceShare`, `create_waypoint`/`create_track`,
and `can_view_resource`. It also has a working auth layer
([Auth API design](2026-08-15-auth-api-design.md)): `get_current_user`,
JWT-based login. None of this is reachable over HTTP for map data yet — the
only endpoints are `/health` and `/auth/*`.

This spec defines the first CRUD surface for map resources: creating,
listing, reading, updating, and soft-deleting waypoints and tracks, plus
managing who a resource is shared with. It is the API-facing counterpart to
the schema work already done.

## Decisions

### 1. Separate routes per resource type; shared routes for sharing

`POST/GET/PATCH/DELETE /waypoints[/{id}]` and the same shape under
`/tracks` are independent routers — each knows its own GeoJSON geometry
type (`Point` vs `LineString`) and doesn't need to branch on a `type` query
param. Sharing, by contrast, operates purely on `resources.id` and is
identical regardless of resource type (`can_view_resource`/`can_edit_resource`
already work on `Resource`, not on `Waypoint`/`Track`), so it gets one
shared set of routes: `POST/GET /resources/{id}/shares`,
`DELETE /resources/{id}/shares/{share_id}`. This avoids duplicating
sharing logic under both `/waypoints/{id}/shares` and `/tracks/{id}/shares`.

### 2. Geometry format: GeoJSON

Request/response bodies carry geometry as GeoJSON
(`{"type": "Point", "coordinates": [lon, lat]}`,
`{"type": "LineString", "coordinates": [[lon, lat], ...]}`), converted
to/from PostGIS via `shapely.geometry.shape()` /
`geoalchemy2.shape.from_shape()` / `to_shape()`. Chosen because the
project's map rendering engine is MapLibre Native, which is GeoJSON-native —
the API speaking the same format avoids a translation layer on the client.
A `/waypoints` endpoint that receives a `LineString` (or any type other than
`Point`) rejects it with `422`; symmetrically for `/tracks` and `Point`.

### 3. New authorization rule: `can_edit_resource`

Added to `app/services/authorization.py`, alongside the existing
`can_view_resource`:

```
can_edit_resource(db, user, resource) -> bool:
    True if resource is not soft-deleted and:
      - user.id == resource.owner_id, OR
      - a ResourceShare exists for this resource with permission=EDIT,
        scoped to this user or to this user's organization
    False otherwise (including soft-deleted user).
```

Unlike `can_view_resource`, organization `owner`/`admin` roles do **not**
grant edit rights automatically — that role only grants view-oversight, per
the original roles design (§3 of the 2026-08-12 spec: "owner and admin
always see all resources... A resource becomes visible to others only via
explicit sharing" — edit access follows the same explicit-only principle,
just one step further than view).

### 4. Access-denied on read: 403, not 404

`GET /waypoints/{id}` (and `/tracks/{id}`) on a resource that exists but the
caller cannot view returns `403 Forbidden`, not `404 Not Found`. This is an
explicit choice to *not* hide resource existence — acceptable here because
resource IDs are UUIDs (not enumerable/guessable) and the org boundary is
already enforced by `can_view_resource`. A truly nonexistent ID (or one
that is soft-deleted) returns `404`.

### 5. Update: `PATCH`, partial

`PATCH /waypoints/{id}` / `/tracks/{id}` accepts a body where `name` and/or
`geom` are both optional — only supplied fields are changed. Chosen over
`PUT` full-replace because mobile clients frequently need to rename a
waypoint without resending its (potentially large, for tracks) geometry.
Requires `can_edit_resource`.

### 6. Delete: soft delete

`DELETE /waypoints/{id}` / `/tracks/{id}` sets `resources.deleted_at`
(the parent row), consistent with the rest of the schema's soft-delete
convention. Requires `can_edit_resource`. Soft-deleted resources are
excluded from list/get/update/delete (they 404) and from sharing.

### 7. List: everything the caller can view, with pagination

`GET /waypoints` / `/tracks` returns every non-deleted resource of that
type the caller can view under `can_view_resource` — own resources, plus
anything explicitly shared to them or their org, plus (if `owner`/`admin`)
everything else in their org. Supports optional `?limit=&offset=` query
params (default `limit=50`, no offset limit) so the contract doesn't need
to change when result sets grow; omitting them returns the first 50.

### 8. Sharing: who can manage it

`POST /resources/{id}/shares` (create), `GET /resources/{id}/shares` (list
existing shares on a resource), and `DELETE /resources/{id}/shares/{share_id}`
(revoke) all require `can_edit_resource` on the target resource — the same
rule as editing the resource itself. This means an EDIT-shared user can
extend sharing to others (no privilege escalation beyond what they already
have: they can't grant EDIT to someone who then out-ranks them, since EDIT
is the ceiling permission already). `shared_with_user_id` (for `scope=user`)
must belong to the resource's own organization — sharing outside the org is
out of scope (matches the original design's explicit non-goal: "Sharing...
with users outside the organization" is deferred).

## Request/response shapes

```
POST /waypoints
  in:  { "name": str, "geom": GeoJSON Point }
  201: { "id": uuid, "name": str, "geom": GeoJSON Point,
         "org_id": uuid, "owner_id": uuid, "created_at": str }
  422: invalid GeoJSON, wrong geometry type, empty name

GET /waypoints?limit=&offset=
  200: { "items": [WaypointResponse, ...], "limit": int, "offset": int }

GET /waypoints/{id}
  200: WaypointResponse
  403: exists, no view access
  404: does not exist / soft-deleted

PATCH /waypoints/{id}
  in:  { "name"?: str, "geom"?: GeoJSON Point }
  200: WaypointResponse
  403: no edit access (includes: has view but not edit)
  404: does not exist / soft-deleted
  422: invalid GeoJSON / wrong geometry type if geom supplied

DELETE /waypoints/{id}
  204: soft-deleted
  403: no edit access
  404: does not exist / soft-deleted already

-- /tracks: identical shapes, geom is GeoJSON LineString --

POST /resources/{id}/shares
  in:  { "scope": "user"|"organization", "permission": "view"|"edit",
         "shared_with_user_id"?: uuid }
  201: { "id": uuid, "resource_id": uuid, "scope": str, "permission": str,
         "shared_with_user_id": uuid|null, "created_by": uuid, "created_at": str }
  403: no edit access on the resource
  404: resource does not exist / soft-deleted
  422: scope=user without shared_with_user_id (or vice versa),
       shared_with_user_id not in the resource's organization

GET /resources/{id}/shares
  200: { "items": [ShareResponse, ...] }
  403: no edit access on the resource
  404: resource does not exist / soft-deleted

DELETE /resources/{id}/shares/{share_id}
  204: revoked
  403: no edit access on the resource
  404: resource or share does not exist
```

## Components

- `app/schemas/geometry.py` — `GeoJSONPoint`, `GeoJSONLineString` Pydantic
  models (`type` literal + `coordinates`), plus helpers to convert
  to/from `shapely`/PostGIS.
- `app/schemas/waypoints.py` / `app/schemas/tracks.py` — `*CreateRequest`,
  `*UpdateRequest`, `*Response`, `*ListResponse`.
- `app/schemas/shares.py` — `ShareCreateRequest`, `ShareResponse`,
  `ShareListResponse`.
- `app/services/authorization.py` — adds `can_edit_resource` alongside the
  existing `can_view_resource`.
- `app/routers/waypoints.py`, `app/routers/tracks.py`, `app/routers/shares.py`
  — thin HTTP layer, delegate to existing services
  (`create_waypoint`/`create_track`) plus new query/update/delete logic and
  the new `can_edit_resource` check.
- `app/main.py` — mounts the three new routers.

## Error handling

| Condition | Response |
|---|---|
| Resource id well-formed but not found / soft-deleted | 404 |
| Resource exists, caller lacks view access | 403 |
| Resource exists, caller has view but not edit (write ops) | 403 |
| GeoJSON malformed or wrong geometry type for the endpoint | 422 |
| Share `scope`/`shared_with_user_id` inconsistent (mirrors the DB
  CHECK constraint) | 422 |
| `shared_with_user_id` not in the resource's organization | 422 |

## Testing approach

- `can_edit_resource` unit tests: owner, EDIT-shared user (both scopes),
  VIEW-shared user (must be False), org owner/admin with no explicit share
  (must be False — the key behavioral difference from `can_view_resource`),
  soft-deleted resource, soft-deleted user.
- Per-endpoint HTTP tests via the existing `client` fixture: happy path,
  403 on no-view, 403 on view-but-not-edit, 404 on nonexistent/deleted,
  422 on bad geometry, pagination (`limit`/`offset` respected), soft
  delete removes from list/get.
- GeoJSON round-trip test: POST a Point/LineString, GET it back, assert
  coordinates match (within floating-point tolerance).
- Sharing: create share as owner, as EDIT-shared user (should succeed),
  as VIEW-shared user (should 403); revoke; share to a user outside the
  resource's org rejected with 422.

## Out of scope (deliberately deferred)

- Sharing to users outside the resource's organization.
- Bulk operations (bulk create/delete).
- Filtering the list endpoints beyond pagination (e.g. by bounding box,
  by owner) — a natural follow-up once there's real usage data on what
  clients actually need.
- Distance/area measurement endpoints — not part of the resource CRUD
  surface, a separate feature.
- Real-time propagation of shares/updates (WebSocket/Redis pub-sub, per
  the original roadmap's phase 4) — this spec is REST-only.
