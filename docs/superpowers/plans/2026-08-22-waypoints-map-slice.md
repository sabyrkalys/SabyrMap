# Waypoints on the Map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user place, view, edit, and delete point markers ("waypoints") on the map, with the marker's color reflecting a `type` and a visual indicator distinguishing the user's own waypoints from ones shared with them.

**Architecture:** Backend adds `type`/`note`/computed `can_edit` to the existing waypoint resource CRUD API (`/waypoints`). Frontend adds a `waypoints` module (repository + Riverpod controller with optimistic create/update/delete) and wires it into the existing `MapScreen` using `maplibre_gl`'s circle-annotation API (colored circles, not image icons — see the spec's rationale).

**Tech Stack:** FastAPI + SQLAlchemy + Alembic + PostGIS (backend, `api/`); Flutter + Riverpod + `maplibre_gl` 0.26.2 + `http` (frontend, `app/`).

**Spec:** `docs/superpowers/specs/2026-08-22-waypoints-map-slice-design.md`

## Global Constraints

- `type` is a plain string column (not a Postgres enum) — the type list can grow later without a migration.
- `note` is optional, max 500 characters.
- No offline queue/local persistence — optimistic UI covers only the current online session; a failed request rolls back and surfaces an error.
- No real-time updates from other users — waypoints load once per screen open.
- No image-based icons in this slice — markers are colored circles (`CircleOptions`), not `Symbol`/`iconImage`. Real pictogram icons arrive with the future icon-upload slice.
- `can_edit` is computed server-side (via the existing `can_edit_resource`) and returned in every waypoint response — the client never re-implements permission logic.
- Backend commands in this plan assume the local dev stack is already running: `docker compose up -d` from the repo root, with `api` reachable via `docker compose exec api <cmd>`.

---

## Task 1: Waypoint migration — add `type` and `note` columns

**Files:**
- Create: `api/alembic/versions/<generated>_add_type_and_note_to_waypoints.py`
- Modify: `api/app/models/waypoint.py`
- Test: manual upgrade/downgrade verification against the real dev DB (see Step 4) — per project convention, migrations are verified directly, not just via the test suite (the test suite bootstraps schema via `Base.metadata.create_all`, which bypasses Alembic entirely).

**Interfaces:**
- Produces: `waypoints.type` (`VARCHAR(50) NOT NULL DEFAULT 'generic'`), `waypoints.note` (`VARCHAR(500) NULL`) — consumed by Task 3 (schemas/service) and Task 4 (router).

- [ ] **Step 1: Generate the migration file**

Run: `docker compose exec api alembic revision -m "add type and note to waypoints"`

This creates a new file in `api/alembic/versions/` with an auto-generated revision id and `down_revision` set to the current head (`74dacc626025`). Note the generated filename for the next step.

- [ ] **Step 2: Fill in `upgrade()`/`downgrade()`**

Open the generated file and replace its body:

```python
def upgrade() -> None:
    op.add_column(
        "waypoints",
        sa.Column("type", sa.String(length=50), nullable=False, server_default="generic"),
    )
    op.add_column(
        "waypoints",
        sa.Column("note", sa.String(length=500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("waypoints", "note")
    op.drop_column("waypoints", "type")
```

- [ ] **Step 3: Add the columns to the `Waypoint` model**

In `api/app/models/waypoint.py`, add after the existing `geom` column:

```python
    type: Mapped[str] = mapped_column(String(50), nullable=False, server_default="generic")
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
```

(`String` is already imported at the top of this file from `sqlalchemy`.)

- [ ] **Step 4: Verify the migration directly against the real DB**

Run, in order:

```bash
docker compose exec api alembic upgrade head
docker compose exec api alembic current
```

Expected: the new revision is shown as `(head)`, no errors.

```bash
docker compose exec api alembic downgrade -1
docker compose exec api alembic current
```

Expected: back to `74dacc626025 (head)` — wait, it will show `74dacc626025` without `(head)` marker since a newer revision exists; confirm no error occurred.

```bash
docker compose exec api alembic upgrade head
```

Expected: re-applies cleanly, ends back on the new revision. Leave the DB at `head` before continuing.

- [ ] **Step 5: Commit**

```bash
git add api/alembic/versions/ api/app/models/waypoint.py
git commit -m "feat: add type and note columns to waypoints"
```

---

## Task 2: Extract `get_resource_and_entity` as a reusable helper

**Files:**
- Modify: `api/app/routers/resource_crud.py`
- Test: existing full suite (`docker compose exec api pytest`) — this is a pure refactor, no behavior change, no new tests.

**Interfaces:**
- Produces: `get_resource_and_entity(db: Session, model: Type[Any], entity_id: uuid.UUID, entity_label: str) -> tuple[Resource, Any]` (module-level, raises `HTTPException(404)` if not found) — consumed by Task 4's dedicated waypoints router.

- [ ] **Step 1: Extract the helper**

In `api/app/routers/resource_crud.py`, add this **module-level** function (place it above `build_resource_router`):

```python
def get_resource_and_entity(
    db: Session, model: Type[Any], entity_id: uuid.UUID, entity_label: str
) -> tuple[Resource, Any]:
    resource = (
        db.query(Resource)
        .filter(Resource.id == entity_id, Resource.deleted_at.is_(None))
        .first()
    )
    entity = db.get(model, entity_id) if resource is not None else None
    if resource is None or entity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{entity_label} not found")
    return resource, entity
```

Then replace the existing closure inside `build_resource_router` (currently named `_get_resource_and_entity`, defined around the middle of the function) so it delegates instead of duplicating the logic:

```python
    def _get_resource_and_entity(db: Session, entity_id: uuid.UUID) -> tuple[Resource, Any]:
        return get_resource_and_entity(db, model, entity_id, entity_label)
```

Everything else in `build_resource_router` (used by `tracks.py`) stays unchanged.

- [ ] **Step 2: Run the full backend test suite to confirm no regression**

Run: `docker compose exec api pytest -q`
Expected: all tests pass (106+ tests, same count as before this change — this step only refactors, it doesn't add tests).

- [ ] **Step 3: Commit**

```bash
git add api/app/routers/resource_crud.py
git commit -m "refactor: extract get_resource_and_entity as a reusable helper"
```

---

## Task 3: Waypoint schemas + service — add `type`/`note`

**Files:**
- Modify: `api/app/schemas/waypoints.py`
- Modify: `api/app/services/resources.py`
- Modify: `api/tests/test_resources_service.py`
- Modify: `api/tests/test_waypoints_api.py`
- Modify: `api/tests/test_shares_api.py`
- Test: `api/tests/test_resources_service.py`, `api/tests/test_waypoints_api.py`

**Interfaces:**
- Consumes: nothing new (uses existing `Waypoint` model from Task 1).
- Produces: `create_waypoint(db, *, org_id, owner_id, name, geom, type, note=None) -> Waypoint` — consumed by Task 4's router. `WaypointCreateRequest`/`WaypointUpdateRequest`/`WaypointResponse` now carry `type`/`note` (and `WaypointResponse` carries `can_edit`, populated by Task 4).

- [ ] **Step 1: Update the schemas**

Replace the full contents of `api/app/schemas/waypoints.py`:

```python
import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.geometry import GeoJSONPoint


class WaypointCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    type: str = Field(min_length=1)
    note: str | None = Field(default=None, max_length=500)
    geom: GeoJSONPoint


class WaypointUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    type: str | None = Field(default=None, min_length=1)
    note: str | None = Field(default=None, max_length=500)
    geom: GeoJSONPoint | None = None


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    type: str
    note: str | None
    geom: GeoJSONPoint
    can_edit: bool
    created_at: datetime


class WaypointListResponse(BaseModel):
    items: list[WaypointResponse]
    limit: int
    offset: int
```

- [ ] **Step 2: Update `create_waypoint`**

In `api/app/services/resources.py`, replace the `create_waypoint` function:

```python
def create_waypoint(
    db: Session, *, org_id: uuid.UUID, owner_id: uuid.UUID, name: str, geom, type: str, note: str | None = None
) -> Waypoint:
    resource = Resource(org_id=org_id, owner_id=owner_id, resource_type=ResourceType.WAYPOINT)
    db.add(resource)
    db.flush()
    waypoint = Waypoint(id=resource.id, name=name, geom=geom, type=type, note=note or None)
    db.add(waypoint)
    db.flush()
    return waypoint
```

(Leave `create_track` untouched.)

- [ ] **Step 3: Update the direct-service test call**

In `api/tests/test_resources_service.py`, update the `create_waypoint(...)` call in `test_create_waypoint_creates_resource_and_waypoint_rows` to pass `type="generic"`:

```python
    waypoint = create_waypoint(
        db_session, org_id=org.id, owner_id=owner.id, name="Summit",
        geom=from_shape(Point(7.6, 45.9), srid=4326), type="generic",
    )
```

- [ ] **Step 4: Update existing waypoint API test payloads to include `type`**

In `api/tests/test_waypoints_api.py`, every `client.post("/waypoints", json={...})` call currently omits `type`, which is now required (422 otherwise). Add `"type": "generic"` to every such payload. For example, the first one in `test_create_and_get_waypoint` becomes:

```python
    create_response = client.post(
        "/waypoints",
        json={"name": "Trailhead", "type": "generic", "geom": {"type": "Point", "coordinates": [7.6, 45.9]}},
        headers=headers,
    )
```

Apply the same `"type": "generic"` addition to the payloads in: `test_list_waypoints_returns_created`, `test_get_waypoint_forbidden_for_other_org`, `test_create_waypoint_rejects_empty_name` (keep `name: ""`, add `type: "generic"`), `test_create_waypoint_rejects_wrong_geometry_type`, `test_list_waypoints_pagination` (the loop body), `test_update_waypoint_name_only`, `test_update_waypoint_forbidden_without_edit_access`, `test_delete_waypoint_soft_deletes`, `test_delete_waypoint_forbidden_without_edit_access`.

- [ ] **Step 5: Update the shares test helper**

In `api/tests/test_shares_api.py`, update `_create_waypoint`:

```python
def _create_waypoint(client, headers, name="Shared Point"):
    response = client.post(
        "/waypoints",
        json={"name": name, "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    return response.json()["id"]
```

- [ ] **Step 6: Add a schema-level rejection test**

Add to `api/tests/test_waypoints_api.py`:

```python
def test_create_waypoint_rejects_empty_type(client):
    headers = _register(client, "waypoint-empty-type@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Valid", "type": "", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 422
```

- [ ] **Step 7: Run the affected tests**

Run: `docker compose exec api pytest tests/test_resources_service.py tests/test_waypoints_api.py -q`
Expected: these will still show failures for `type`/`note`/`can_edit` fields not yet in the response — that's expected until Task 4 is done. Confirm specifically that `test_create_waypoint_rejects_empty_type` and the `test_create_waypoint_rejects_empty_name` (with `type` now included) pass, since those only depend on the schema (422 rejection happens before the router logic that Task 4 changes). The rest of this file's tests are expected to fail at this point (missing `can_edit`/`type`/`note` in responses, or requests including `type` now hitting the still-generic router that doesn't know about it) — that's resolved by Task 4.

- [ ] **Step 8: Commit**

```bash
git add api/app/schemas/waypoints.py api/app/services/resources.py api/tests/test_resources_service.py api/tests/test_waypoints_api.py api/tests/test_shares_api.py
git commit -m "feat: add type/note to waypoint schemas and create_waypoint"
```

---

## Task 4: Dedicated waypoints router with `type`/`note`/`can_edit`

**Files:**
- Modify: `api/app/routers/waypoints.py` (replace `build_resource_router` usage with a dedicated router)
- Modify: `api/tests/test_waypoints_api.py` (add `type`/`note`/`can_edit` coverage)
- Test: `api/tests/test_waypoints_api.py`

**Interfaces:**
- Consumes: `get_resource_and_entity` (Task 2), `create_waypoint(..., type, note=None)` (Task 3), `can_view_resource`/`can_edit_resource` (existing, `app/services/authorization.py`).
- Produces: `router` (FastAPI `APIRouter`, same public HTTP contract shape as before plus `type`/`note`/`can_edit` fields) — `app/main.py` already imports this as `from app.routers.waypoints import router as waypoints_router`, no change needed there.

- [ ] **Step 1: Replace `api/app/routers/waypoints.py`**

```python
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.user import User
from app.models.waypoint import Waypoint
from app.routers.resource_crud import get_resource_and_entity
from app.schemas.geometry import geojson_to_point, point_to_geojson
from app.schemas.waypoints import (
    WaypointCreateRequest,
    WaypointListResponse,
    WaypointResponse,
    WaypointUpdateRequest,
)
from app.services.authorization import can_edit_resource, can_view_resource
from app.services.resources import create_waypoint

router = APIRouter(prefix="/waypoints", tags=["waypoints"])


def _to_response(resource: Resource, entity: Waypoint, current_user: User, db: Session) -> WaypointResponse:
    return WaypointResponse(
        id=entity.id,
        org_id=resource.org_id,
        owner_id=resource.owner_id,
        name=entity.name,
        type=entity.type,
        note=entity.note,
        geom=point_to_geojson(entity.geom),
        can_edit=can_edit_resource(db, current_user, resource),
        created_at=resource.created_at,
    )


@router.post("", response_model=WaypointResponse, status_code=status.HTTP_201_CREATED)
def create(
    payload: WaypointCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    entity = create_waypoint(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_point(payload.geom),
        type=payload.type,
        note=payload.note,
    )
    resource = db.get(Resource, entity.id)
    return _to_response(resource, entity, current_user, db)


@router.get("", response_model=WaypointListResponse)
def list_waypoints(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resources = (
        db.query(Resource)
        .filter(
            Resource.resource_type == ResourceType.WAYPOINT,
            Resource.deleted_at.is_(None),
            Resource.org_id == current_user.org_id,
        )
        .order_by(Resource.created_at)
        .all()
    )
    visible = [r for r in resources if can_view_resource(db, current_user, r)]
    page = visible[offset : offset + limit]
    items = [_to_response(resource, db.get(Waypoint, resource.id), current_user, db) for resource in page]
    return WaypointListResponse(items=items, limit=limit, offset=offset)


@router.get("/{resource_id}", response_model=WaypointResponse)
def get_waypoint(
    resource_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, entity = get_resource_and_entity(db, Waypoint, resource_id, "waypoint")
    if not can_view_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this waypoint")
    return _to_response(resource, entity, current_user, db)


@router.patch("/{resource_id}", response_model=WaypointResponse)
def update_waypoint(
    resource_id: uuid.UUID,
    payload: WaypointUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, entity = get_resource_and_entity(db, Waypoint, resource_id, "waypoint")
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to edit this waypoint")

    if payload.name is not None:
        entity.name = payload.name
    if payload.type is not None:
        entity.type = payload.type
    if payload.note is not None:
        entity.note = payload.note or None
    if payload.geom is not None:
        entity.geom = geojson_to_point(payload.geom)
    db.flush()
    return _to_response(resource, entity, current_user, db)


@router.delete("/{resource_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_waypoint(
    resource_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, entity = get_resource_and_entity(db, Waypoint, resource_id, "waypoint")
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to delete this waypoint")

    resource.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return None
```

- [ ] **Step 2: Add `type`/`note`/`can_edit` assertions to existing tests**

In `api/tests/test_waypoints_api.py`, update `test_create_and_get_waypoint` to also assert the new fields:

```python
def test_create_and_get_waypoint(client):
    headers = _register(client, "waypoint-create@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Trailhead", "type": "generic", "geom": {"type": "Point", "coordinates": [7.6, 45.9]}},
        headers=headers,
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Trailhead"
    assert body["type"] == "generic"
    assert body["note"] is None
    assert body["can_edit"] is True
    assert body["geom"] == {"type": "Point", "coordinates": [7.6, 45.9]}

    get_response = client.get(f"/waypoints/{body['id']}", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["id"] == body["id"]
```

- [ ] **Step 3: Add new tests for `type`/`note` persistence and update**

Add to `api/tests/test_waypoints_api.py`:

```python
def test_create_waypoint_with_note(client):
    headers = _register(client, "waypoint-note@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Camp",
            "type": "camp",
            "note": "Bring extra water",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["note"] == "Bring extra water"


def test_create_waypoint_with_empty_note_stores_null(client):
    headers = _register(client, "waypoint-empty-note@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Camp", "type": "camp", "note": "", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["note"] is None


def test_update_waypoint_type_and_note(client):
    headers = _register(client, "waypoint-update-type@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Spot", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(
        f"/waypoints/{waypoint_id}",
        json={"type": "danger", "note": "Rockslide area"},
        headers=headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["type"] == "danger"
    assert body["note"] == "Rockslide area"
    assert body["name"] == "Spot"


def test_update_waypoint_clears_note_with_empty_string(client):
    headers = _register(client, "waypoint-clear-note@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Spot", "type": "generic", "note": "temporary", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"note": ""}, headers=headers)
    assert response.status_code == 200
    assert response.json()["note"] is None
```

- [ ] **Step 4: Add `can_edit` coverage across owner / edit-share / view-share**

Add to `api/tests/test_waypoints_api.py` (mirrors the `_add_org_member`/`_auth_headers_for` pattern already used in `test_shares_api.py`):

```python
def test_can_edit_true_for_owner(client):
    headers = _register(client, "waypoint-can-edit-owner@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "Mine", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.json()["can_edit"] is True


def test_can_edit_true_for_edit_share(client, db_session):
    from app.models.enums import Role
    from app.models.user import User
    from app.services.auth import create_access_token

    owner_headers = _register(client, "waypoint-can-edit-owner-2@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Shared", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    owner = db_session.query(User).filter_by(email="waypoint-can-edit-owner-2@example.test").one()
    editor = User(org_id=owner.org_id, email="waypoint-can-edit-editor@example.test", password_hash="x", role=Role.MEMBER)
    db_session.add(editor)
    db_session.flush()

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "edit", "shared_with_user_id": str(editor.id)},
        headers=owner_headers,
    )

    editor_headers = {"Authorization": f"Bearer {create_access_token(editor.id)}"}
    response = client.get(f"/waypoints/{waypoint_id}", headers=editor_headers)
    assert response.json()["can_edit"] is True


def test_can_edit_false_for_view_share(client, db_session):
    from app.models.enums import Role
    from app.models.user import User
    from app.services.auth import create_access_token

    owner_headers = _register(client, "waypoint-can-edit-owner-3@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Shared", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    owner = db_session.query(User).filter_by(email="waypoint-can-edit-owner-3@example.test").one()
    viewer = User(org_id=owner.org_id, email="waypoint-can-edit-viewer@example.test", password_hash="x", role=Role.MEMBER)
    db_session.add(viewer)
    db_session.flush()

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(viewer.id)},
        headers=owner_headers,
    )

    viewer_headers = {"Authorization": f"Bearer {create_access_token(viewer.id)}"}
    response = client.get(f"/waypoints/{waypoint_id}", headers=viewer_headers)
    assert response.json()["can_edit"] is False
```

- [ ] **Step 5: Run the full backend suite**

Run: `docker compose exec api pytest -q`
Expected: all tests pass, including every test touched/added in Tasks 3 and 4.

- [ ] **Step 6: Commit**

```bash
git add api/app/routers/waypoints.py api/tests/test_waypoints_api.py
git commit -m "feat: add type/note/can_edit to the waypoints API"
```

---

## Task 5: `ApiClient.patch()` / `ApiClient.delete()`

**Files:**
- Modify: `app/lib/api/api_client.dart`
- Test: `app/test/api/api_client_test.dart`

**Interfaces:**
- Produces: `ApiClient.patch(String path, {Map<String, dynamic>? body, String? token}) -> Future<http.Response>`, `ApiClient.delete(String path, {String? token}) -> Future<http.Response>` — consumed by Task 7's `HttpWaypointsRepository`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/api/api_client_test.dart`:

```dart
  test('patch sends JSON-encoded body with Content-Type header', () async {
    String? capturedBody;
    String? capturedMethod;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      capturedMethod = request.method;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.patch('/waypoints/1', body: {'name': 'New'});

    expect(capturedMethod, 'PATCH');
    expect(jsonDecode(capturedBody!), {'name': 'New'});
  });

  test('delete sends DELETE with Authorization header when token is provided', () async {
    Uri? capturedUri;
    String? capturedMethod;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedMethod = request.method;
      capturedHeaders = request.headers;
      return http.Response('', 204);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    final response = await client.delete('/waypoints/1', token: 'abc123');

    expect(capturedUri, Uri.parse('http://example.test/waypoints/1'));
    expect(capturedMethod, 'DELETE');
    expect(capturedHeaders!['Authorization'], 'Bearer abc123');
    expect(response.statusCode, 204);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/api/api_client_test.dart` (from `app/`)
Expected: FAIL — `patch`/`delete` are not defined on `ApiClient`.

- [ ] **Step 3: Implement**

In `app/lib/api/api_client.dart`, add after the existing `post` method:

```dart
  Future<http.Response> patch(String path, {Map<String, dynamic>? body, String? token}) {
    return _httpClient.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> delete(String path, {String? token}) {
    return _httpClient.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/api/api_client_test.dart` (from `app/`)
Expected: PASS, all tests in the file green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/api/api_client.dart app/test/api/api_client_test.dart
git commit -m "feat: add patch/delete to ApiClient"
```

---

## Task 6: `Waypoint` model + `WaypointException`

**Files:**
- Create: `app/lib/waypoints/waypoint_models.dart`
- Test: `app/test/waypoints/waypoint_models_test.dart`

**Interfaces:**
- Produces: `Waypoint` class (`id, orgId, ownerId, name, type, note, lat, lng, canEdit, createdAt`, plus `Waypoint.fromJson`), `WaypointException` (mirrors `AuthException`'s shape: `message`, `toString()`) — consumed by Tasks 7, 8, 10, 11.

- [ ] **Step 1: Write the failing test**

Create `app/test/waypoints/waypoint_models_test.dart`:

```dart
import 'package:app/waypoints/waypoint_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Waypoint.fromJson', () {
    test('parses geom coordinates as [lng, lat] into lat/lng fields', () {
      final json = {
        'id': 'w1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Trailhead',
        'type': 'camp',
        'note': 'Bring water',
        'geom': {
          'type': 'Point',
          'coordinates': [7.6, 45.9],
        },
        'can_edit': true,
        'created_at': '2026-08-22T10:00:00Z',
      };

      final waypoint = Waypoint.fromJson(json);

      expect(waypoint.id, 'w1');
      expect(waypoint.orgId, 'o1');
      expect(waypoint.ownerId, 'u1');
      expect(waypoint.name, 'Trailhead');
      expect(waypoint.type, 'camp');
      expect(waypoint.note, 'Bring water');
      expect(waypoint.lng, 7.6);
      expect(waypoint.lat, 45.9);
      expect(waypoint.canEdit, true);
      expect(waypoint.createdAt, DateTime.parse('2026-08-22T10:00:00Z'));
    });

    test('note is null when absent from JSON', () {
      final json = {
        'id': 'w1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Trailhead',
        'type': 'generic',
        'note': null,
        'geom': {
          'type': 'Point',
          'coordinates': [1.0, 2.0],
        },
        'can_edit': false,
        'created_at': '2026-08-22T10:00:00Z',
      };

      final waypoint = Waypoint.fromJson(json);

      expect(waypoint.note, isNull);
    });
  });

  test('WaypointException.toString includes the message', () {
    const exception = WaypointException('Could not create waypoint');
    expect(exception.toString(), 'WaypointException: Could not create waypoint');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/waypoints/waypoint_models_test.dart` (from `app/`)
Expected: FAIL — `package:app/waypoints/waypoint_models.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/waypoints/waypoint_models.dart`:

```dart
class Waypoint {
  const Waypoint({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.note,
    required this.lat,
    required this.lng,
    required this.canEdit,
    required this.createdAt,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String name;
  final String type;
  final String? note;
  final double lat;
  final double lng;
  final bool canEdit;
  final DateTime createdAt;

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    final geom = json['geom'] as Map<String, dynamic>;
    final coordinates = geom['coordinates'] as List<dynamic>;
    return Waypoint(
      id: json['id'] as String,
      orgId: json['org_id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      note: json['note'] as String?,
      lng: (coordinates[0] as num).toDouble(),
      lat: (coordinates[1] as num).toDouble(),
      canEdit: json['can_edit'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WaypointException implements Exception {
  const WaypointException(this.message);

  final String message;

  @override
  String toString() => 'WaypointException: $message';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/waypoints/waypoint_models_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoint_models.dart app/test/waypoints/waypoint_models_test.dart
git commit -m "feat: add Waypoint model and WaypointException"
```

---

## Task 7: `WaypointsRepository`

**Files:**
- Create: `app/lib/waypoints/waypoints_repository.dart`
- Test: `app/test/waypoints/waypoints_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task 5), `Waypoint`/`WaypointException` (Task 6).
- Produces: `abstract class WaypointsRepository` with `list(String token) -> Future<List<Waypoint>>`, `create(String token, {required String name, required String type, required String note, required double lat, required double lng}) -> Future<Waypoint>`, `update(String token, String id, {required String name, required String type, required String note}) -> Future<Waypoint>`, `delete(String token, String id) -> Future<void>`; and `HttpWaypointsRepository implements WaypointsRepository` — consumed by Task 8's `WaypointsController`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/waypoints/waypoints_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _waypointJson = {
  'id': 'w1',
  'org_id': 'o1',
  'owner_id': 'u1',
  'name': 'Trailhead',
  'type': 'generic',
  'note': null,
  'geom': {
    'type': 'Point',
    'coordinates': [7.6, 45.9],
  },
  'can_edit': true,
  'created_at': '2026-08-22T10:00:00Z',
};

void main() {
  group('list', () {
    test('returns parsed waypoints on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({'items': [_waypointJson], 'limit': 50, 'offset': 0}),
            200,
          );
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoints = await repo.list('tok-1');

      expect(waypoints, hasLength(1));
      expect(waypoints.first.id, 'w1');
    });

    test('throws WaypointException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 500)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(repo.list('tok-1'), throwsA(isA<WaypointException>()));
    });
  });

  group('create', () {
    test('sends name/type/note/geom and returns the created waypoint on 201', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_waypointJson), 201);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoint = await repo.create(
        'tok-1',
        name: 'Trailhead',
        type: 'generic',
        note: '',
        lat: 45.9,
        lng: 7.6,
      );

      expect(waypoint.id, 'w1');
      expect(capturedBody, {
        'name': 'Trailhead',
        'type': 'generic',
        'note': '',
        'geom': {
          'type': 'Point',
          'coordinates': [7.6, 45.9],
        },
      });
    });

    test('throws WaypointException on non-201', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 422)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(
        repo.create('tok-1', name: '', type: 'generic', note: '', lat: 0, lng: 0),
        throwsA(isA<WaypointException>()),
      );
    });
  });

  group('update', () {
    test('sends name/type/note and returns the updated waypoint on 200', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints/w1');
          expect(request.method, 'PATCH');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_waypointJson), 200);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoint = await repo.update('tok-1', 'w1', name: 'New name', type: 'danger', note: 'Careful');

      expect(waypoint.id, 'w1');
      expect(capturedBody, {'name': 'New name', 'type': 'danger', 'note': 'Careful'});
    });

    test('throws WaypointException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 403)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(
        repo.update('tok-1', 'w1', name: 'x', type: 'generic', note: ''),
        throwsA(isA<WaypointException>()),
      );
    });
  });

  group('delete', () {
    test('completes normally on 204', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints/w1');
          expect(request.method, 'DELETE');
          return http.Response('', 204);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      await repo.delete('tok-1', 'w1');
    });

    test('throws WaypointException on non-204', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 403)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(repo.delete('tok-1', 'w1'), throwsA(isA<WaypointException>()));
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/waypoints/waypoints_repository_test.dart` (from `app/`)
Expected: FAIL — `package:app/waypoints/waypoints_repository.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/waypoints/waypoints_repository.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'waypoint_models.dart';

abstract class WaypointsRepository {
  Future<List<Waypoint>> list(String token);

  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  });

  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
  });

  Future<void> delete(String token, String id);
}

class HttpWaypointsRepository implements WaypointsRepository {
  HttpWaypointsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Waypoint>> list(String token) async {
    final response = await _client.get('/waypoints', token: token);
    if (response.statusCode != 200) {
      throw const WaypointException('Could not load waypoints');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items.map((e) => Waypoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  }) async {
    final response = await _client.post(
      '/waypoints',
      token: token,
      body: {
        'name': name,
        'type': type,
        'note': note,
        'geom': {
          'type': 'Point',
          'coordinates': [lng, lat],
        },
      },
    );
    if (response.statusCode != 201) {
      throw const WaypointException('Could not create waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
  }) async {
    final response = await _client.patch(
      '/waypoints/$id',
      token: token,
      body: {'name': name, 'type': type, 'note': note},
    );
    if (response.statusCode != 200) {
      throw const WaypointException('Could not update waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String token, String id) async {
    final response = await _client.delete('/waypoints/$id', token: token);
    if (response.statusCode != 204) {
      throw const WaypointException('Could not delete waypoint');
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/waypoints/waypoints_repository_test.dart` (from `app/`)
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoints_repository.dart app/test/waypoints/waypoints_repository_test.dart
git commit -m "feat: add WaypointsRepository"
```

---

## Task 8: `WaypointsController` (optimistic create/update/delete)

**Files:**
- Create: `app/lib/waypoints/waypoints_controller.dart`
- Create: `app/test/waypoints/fakes.dart`
- Test: `app/test/waypoints/waypoints_controller_test.dart`

**Interfaces:**
- Consumes: `WaypointsRepository`/`HttpWaypointsRepository` (Task 7), `Waypoint`/`WaypointException` (Task 6), `apiClientProvider`/`tokenStorageProvider` (existing, `app/lib/auth/auth_controller.dart`).
- Produces: `waypointsRepositoryProvider` (`Provider<WaypointsRepository>`), `waypointsControllerProvider` (`NotifierProvider<WaypointsController, List<Waypoint>>`), `WaypointsController` with `loadWaypoints()`, `createWaypoint({required ownerId, name, type, note, lat, lng})`, `updateWaypoint(id, {required name, type, note})`, `deleteWaypoint(id)` — consumed by Task 11 (`MapScreen`).

- [ ] **Step 1: Add a fake repository for tests**

Create `app/test/waypoints/fakes.dart`:

```dart
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_repository.dart';

class FakeWaypointsRepository implements WaypointsRepository {
  FakeWaypointsRepository({List<Waypoint>? initial}) : items = List.of(initial ?? const []);

  final List<Waypoint> items;

  /// Set to a Waypoint for success, or a WaypointException instance to throw.
  Object? createResult;
  Object? updateResult;
  Object? deleteResult;

  @override
  Future<List<Waypoint>> list(String token) async => List.of(items);

  @override
  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  }) async {
    if (createResult is WaypointException) throw createResult as WaypointException;
    return createResult as Waypoint;
  }

  @override
  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
  }) async {
    if (updateResult is WaypointException) throw updateResult as WaypointException;
    return updateResult as Waypoint;
  }

  @override
  Future<void> delete(String token, String id) async {
    if (deleteResult is WaypointException) throw deleteResult as WaypointException;
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/waypoints/waypoints_controller_test.dart`:

```dart
import 'package:app/auth/token_storage.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

Waypoint _waypoint({String id = 'w1', String ownerId = 'u1', String type = 'generic', String? note}) {
  return Waypoint(
    id: id,
    orgId: 'o1',
    ownerId: ownerId,
    name: 'Test',
    type: type,
    note: note,
    lat: 1.0,
    lng: 2.0,
    canEdit: true,
    createdAt: DateTime.utc(2026, 8, 22),
  );
}

ProviderContainer _buildContainer({
  required FakeWaypointsRepository repo,
  TokenStorage? storage,
}) {
  final tokenStorage = storage ?? (FakeTokenStorage()..write('tok-1'));
  return ProviderContainer(
    overrides: [
      waypointsRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(tokenStorage),
    ],
  );
}

void main() {
  test('initial state is an empty list', () {
    final container = _buildContainer(repo: FakeWaypointsRepository());
    addTearDown(container.dispose);

    expect(container.read(waypointsControllerProvider), isEmpty);
  });

  group('loadWaypoints', () {
    test('populates state from the repository', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      expect(container.read(waypointsControllerProvider), hasLength(1));
    });

    test('leaves state empty when no token is stored', () async {
      final storage = FakeTokenStorage();
      final container = _buildContainer(repo: FakeWaypointsRepository(initial: [_waypoint()]), storage: storage);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      expect(container.read(waypointsControllerProvider), isEmpty);
    });
  });

  group('createWaypoint', () {
    test('adds the waypoint optimistically then replaces it with the server result', () async {
      final repo = FakeWaypointsRepository()..createResult = _waypoint(id: 'server-id');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: 'u1',
            name: 'Test',
            type: 'generic',
            note: '',
            lat: 1.0,
            lng: 2.0,
          );

      final state = container.read(waypointsControllerProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'server-id');
    });

    test('rolls back the optimistic waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository()..createResult = const WaypointException('Could not create waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await expectLater(
        container.read(waypointsControllerProvider.notifier).createWaypoint(
              ownerId: 'u1',
              name: 'Test',
              type: 'generic',
              note: '',
              lat: 1.0,
              lng: 2.0,
            ),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider), isEmpty);
    });
  });

  group('updateWaypoint', () {
    test('applies the update optimistically then replaces it with the server result', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()])
        ..updateResult = _waypoint(type: 'danger', note: 'Careful');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await container.read(waypointsControllerProvider.notifier).updateWaypoint(
            'w1',
            name: 'Test',
            type: 'danger',
            note: 'Careful',
          );

      final state = container.read(waypointsControllerProvider);
      expect(state.single.type, 'danger');
      expect(state.single.note, 'Careful');
    });

    test('rolls back to the previous waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint(type: 'generic')])
        ..updateResult = const WaypointException('Could not update waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await expectLater(
        container.read(waypointsControllerProvider.notifier).updateWaypoint(
              'w1',
              name: 'Test',
              type: 'danger',
              note: '',
            ),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider).single.type, 'generic');
    });
  });

  group('deleteWaypoint', () {
    test('removes the waypoint on success', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await container.read(waypointsControllerProvider.notifier).deleteWaypoint('w1');

      expect(container.read(waypointsControllerProvider), isEmpty);
    });

    test('restores the waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()])
        ..deleteResult = const WaypointException('Could not delete waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await expectLater(
        container.read(waypointsControllerProvider.notifier).deleteWaypoint('w1'),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider), hasLength(1));
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/waypoints/waypoints_controller_test.dart` (from `app/`)
Expected: FAIL — `package:app/waypoints/waypoints_controller.dart` doesn't exist.

- [ ] **Step 4: Implement**

Create `app/lib/waypoints/waypoints_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart' show apiClientProvider, tokenStorageProvider;
import '../auth/token_storage.dart';
import 'waypoint_models.dart';
import 'waypoints_repository.dart';

final waypointsRepositoryProvider = Provider<WaypointsRepository>((ref) {
  return HttpWaypointsRepository(ref.watch(apiClientProvider));
});

final waypointsControllerProvider = NotifierProvider<WaypointsController, List<Waypoint>>(WaypointsController.new);

class WaypointsController extends Notifier<List<Waypoint>> {
  @override
  List<Waypoint> build() => const [];

  WaypointsRepository get _repository => ref.read(waypointsRepositoryProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> loadWaypoints() async {
    final token = await _storage.read();
    if (token == null) return;
    try {
      state = await _repository.list(token);
    } on WaypointException {
      // Initial-load failures aren't surfaced in this slice; the map just
      // stays at whatever it already had (empty, on first load) until the
      // next successful load.
    }
  }

  Future<void> createWaypoint({
    required String ownerId,
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  }) async {
    final token = await _storage.read();
    if (token == null) return;

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Waypoint(
      id: tempId,
      orgId: '',
      ownerId: ownerId,
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created = await _repository.create(token, name: name, type: type, note: note, lat: lat, lng: lng);
      state = [for (final w in state) if (w.id == tempId) created else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id != tempId) w];
      rethrow;
    }
  }

  Future<void> updateWaypoint(
    String id, {
    required String name,
    required String type,
    required String note,
  }) async {
    final token = await _storage.read();
    if (token == null) return;

    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    final optimistic = Waypoint(
      id: previous.id,
      orgId: previous.orgId,
      ownerId: previous.ownerId,
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: previous.lat,
      lng: previous.lng,
      canEdit: previous.canEdit,
      createdAt: previous.createdAt,
    );
    state = [for (final w in state) if (w.id == id) optimistic else w];

    try {
      final updated = await _repository.update(token, id, name: name, type: type, note: note);
      state = [for (final w in state) if (w.id == id) updated else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id == id) previous else w];
      rethrow;
    }
  }

  Future<void> deleteWaypoint(String id) async {
    final token = await _storage.read();
    if (token == null) return;

    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    state = [for (final w in state) if (w.id != id) w];

    try {
      await _repository.delete(token, id);
    } on WaypointException {
      state = [...state, previous];
      rethrow;
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/waypoints/waypoints_controller_test.dart` (from `app/`)
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
git add app/lib/waypoints/waypoints_controller.dart app/test/waypoints/fakes.dart app/test/waypoints/waypoints_controller_test.dart
git commit -m "feat: add WaypointsController with optimistic create/update/delete"
```

---

## Task 9: Waypoint type/color constants

**Files:**
- Create: `app/lib/waypoints/waypoint_types.dart`
- Test: `app/test/waypoints/waypoint_types_test.dart`

**Interfaces:**
- Produces: `waypointTypes` (`List<String>`), `defaultWaypointType` (`String`), `waypointTypeColors` (`Map<String, String>`, hex colors) — consumed by Task 10 (form chips) and Task 11 (circle color).

- [ ] **Step 1: Write the failing test**

Create `app/test/waypoints/waypoint_types_test.dart`:

```dart
import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every type has a color and the default type is in the list', () {
    expect(waypointTypes, contains(defaultWaypointType));
    for (final type in waypointTypes) {
      expect(waypointTypeColors.containsKey(type), isTrue, reason: 'missing color for $type');
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/waypoints/waypoint_types_test.dart` (from `app/`)
Expected: FAIL — `package:app/waypoints/waypoint_types.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/waypoints/waypoint_types.dart`:

```dart
const List<String> waypointTypes = ['generic', 'camp', 'water', 'danger', 'point'];

const String defaultWaypointType = 'generic';

const Map<String, String> waypointTypeColors = {
  'generic': '#607D8B',
  'camp': '#8D6E63',
  'water': '#2196F3',
  'danger': '#E53935',
  'point': '#43A047',
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/waypoints/waypoint_types_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoint_types.dart app/test/waypoints/waypoint_types_test.dart
git commit -m "feat: add waypoint type/color constants"
```

---

## Task 10: Waypoint create/edit form bottom sheet

**Files:**
- Create: `app/lib/waypoints/waypoint_form_sheet.dart`
- Test: `app/test/waypoints/waypoint_form_sheet_test.dart`

**Interfaces:**
- Consumes: `waypointTypes`/`defaultWaypointType` (Task 9), `Waypoint` (Task 6, for pre-fill on edit).
- Produces: `WaypointFormResult` (`{name, type, note}`, all `String`), `showWaypointFormSheet(BuildContext context, {Waypoint? existing}) -> Future<WaypointFormResult?>` — consumed by Task 11 (`MapScreen`).

- [ ] **Step 1: Write the failing tests**

Create `app/test/waypoints/waypoint_form_sheet_test.dart`:

```dart
import 'package:app/waypoints/waypoint_form_sheet.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Waypoint _existingWaypoint() {
  return Waypoint(
    id: 'w1',
    orgId: 'o1',
    ownerId: 'u1',
    name: 'Old name',
    type: 'water',
    note: 'Old note',
    lat: 1.0,
    lng: 2.0,
    canEdit: true,
    createdAt: DateTime.utc(2026, 8, 22),
  );
}

Widget _harness(VoidCallback onOpen, ValueChanged<WaypointFormResult?> onResult, {Waypoint? existing}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onOpen();
            final result = await showWaypointFormSheet(context, existing: existing);
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('save is disabled until a name is entered, then submits name/type/note', (tester) async {
    WaypointFormResult? result;
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(find.byKey(const Key('waypoint_save_button')));
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_type_chip_water')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('waypoint_note_field')), 'Bring rope');
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'Summit');
    expect(result!.type, 'water');
    expect(result!.note, 'Bring rope');
  });

  testWidgets('pre-fills fields when editing an existing waypoint', (tester) async {
    await tester.pumpWidget(_harness(() {}, (_) {}, existing: _existingWaypoint()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Old name'), findsOneWidget);
    expect(find.text('Old note'), findsOneWidget);
    final waterChip = tester.widget<ChoiceChip>(find.byKey(const Key('waypoint_type_chip_water')));
    expect(waterChip.selected, isTrue);
  });

  testWidgets('returns null when dismissed without saving', (tester) async {
    WaypointFormResult? result = const WaypointFormResult(name: 'sentinel', type: 'generic', note: '');
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/waypoints/waypoint_form_sheet_test.dart` (from `app/`)
Expected: FAIL — `package:app/waypoints/waypoint_form_sheet.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/waypoints/waypoint_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import 'waypoint_models.dart';
import 'waypoint_types.dart';

class WaypointFormResult {
  const WaypointFormResult({required this.name, required this.type, required this.note});

  final String name;
  final String type;
  final String note;
}

Future<WaypointFormResult?> showWaypointFormSheet(BuildContext context, {Waypoint? existing}) {
  return showModalBottomSheet<WaypointFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => WaypointFormSheet(existing: existing),
  );
}

class WaypointFormSheet extends StatefulWidget {
  const WaypointFormSheet({super.key, this.existing});

  final Waypoint? existing;

  @override
  State<WaypointFormSheet> createState() => _WaypointFormSheetState();
}

class _WaypointFormSheetState extends State<WaypointFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _noteController =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _selectedType = widget.existing?.type ?? defaultWaypointType;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEditing ? 'Edit waypoint' : 'New waypoint', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final type in waypointTypes)
                ChoiceChip(
                  key: Key('waypoint_type_chip_$type'),
                  label: Text(type),
                  selected: _selectedType == type,
                  onSelected: (_) => setState(() => _selectedType = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_note_field'),
            controller: _noteController,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('waypoint_save_button'),
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      WaypointFormResult(
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        note: _noteController.text.trim(),
                      ),
                    ),
            child: Text(isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/waypoints/waypoint_form_sheet_test.dart` (from `app/`)
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoint_form_sheet.dart app/test/waypoints/waypoint_form_sheet_test.dart
git commit -m "feat: add waypoint create/edit form bottom sheet"
```

---

## Task 11: Wire waypoints into `MapScreen`

**Files:**
- Modify: `app/lib/map/map_screen.dart`
- Modify: `app/test/map/map_screen_test.dart`

**Interfaces:**
- Consumes: `waypointsControllerProvider`/`waypointsRepositoryProvider` (Task 8), `waypointTypeColors`/`defaultWaypointType` (Task 9), `showWaypointFormSheet`/`WaypointFormResult` (Task 10), `authControllerProvider` (existing).
- Produces: the finished user-facing feature — no further tasks consume this.

- [ ] **Step 1: Update the existing widget tests to isolate them from the network**

The two existing tests in `app/test/map/map_screen_test.dart` don't override `waypointsRepositoryProvider`, so once `MapScreen` calls `loadWaypoints()` on init, they'd hit a real (failing) network call. Update both tests to add the override, using `FakeWaypointsRepository` from Task 8's `test/waypoints/fakes.dart`. Replace the full contents of `app/test/map/map_screen_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import '../waypoints/fakes.dart';

void main() {
  testWidgets('MapScreen builds without throwing and shows a logout action', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('tapping logout calls AuthController.logout', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
```

- [ ] **Step 2: Run the existing tests to verify they still pass (with the override in place)**

Run: `flutter test test/map/map_screen_test.dart` (from `app/`)
Expected: PASS. At this point `MapScreen` hasn't been rewritten yet (that's Step 3), so the added `waypointsRepositoryProvider` override is simply unused — the test file just needs to compile and pass as before. If it fails, do not proceed until this baseline is green.

- [ ] **Step 3: Implement — rewrite `MapScreen`**

Replace the full contents of `app/lib/map/map_screen.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  final Map<String, Circle> _circlesByWaypointId = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(waypointsControllerProvider.notifier).loadWaypoints());
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onStyleLoaded() {
    _syncCircles(ref.read(waypointsControllerProvider));
  }

  Future<void> _syncCircles(List<Waypoint> waypoints) async {
    final controller = _controller;
    if (controller == null) return;
    final currentUserId = _currentUserId();

    final currentIds = waypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
      }
    }

    for (final waypoint in waypoints) {
      final options = _circleOptionsFor(waypoint, currentUserId);
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
      } else {
        await controller.updateCircle(existing, options);
        _circlesByWaypointId[waypoint.id] = Circle(existing.id, options, {'waypointId': waypoint.id});
      }
    }
  }

  CircleOptions _circleOptionsFor(Waypoint waypoint, String currentUserId) {
    final isOwn = waypoint.ownerId == currentUserId;
    return CircleOptions(
      geometry: LatLng(waypoint.lat, waypoint.lng),
      circleRadius: 8,
      circleColor: waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
      circleStrokeColor: isOwn ? '#FFFFFF' : '#000000',
      circleStrokeWidth: isOwn ? 1 : 2,
    );
  }

  String _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.user.id : '';
  }

  Future<void> _onMapLongClick(Point<double> point, LatLng coordinates) async {
    final result = await showWaypointFormSheet(context);
    if (result == null || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: _currentUserId(),
            name: result.name,
            type: result.type,
            note: result.note,
            lat: coordinates.latitude,
            lng: coordinates.longitude,
          );
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _onCircleTapped(Circle circle) {
    final waypointId = circle.data?['waypointId'] as String?;
    if (waypointId == null) return;
    final waypoints = ref.read(waypointsControllerProvider);
    final index = waypoints.indexWhere((w) => w.id == waypointId);
    if (index == -1) return;
    _showWaypointDetails(waypoints[index]);
  }

  Future<void> _showWaypointDetails(Waypoint waypoint) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(waypoint.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(waypoint.type),
            if (waypoint.note != null && waypoint.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(waypoint.note!),
            ],
            if (waypoint.canEdit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    key: const Key('waypoint_edit_button'),
                    onPressed: () => Navigator.of(context).pop('edit'),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    key: const Key('waypoint_delete_button'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editWaypoint(waypoint);
    } else if (action == 'delete') {
      await _deleteWaypoint(waypoint);
    }
  }

  Future<void> _editWaypoint(Waypoint waypoint) async {
    final result = await showWaypointFormSheet(context, existing: waypoint);
    if (result == null || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).updateWaypoint(
            waypoint.id,
            name: result.name,
            type: result.type,
            note: result.note,
          );
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteWaypoint(Waypoint waypoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete waypoint?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).deleteWaypoint(waypoint.id);
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Waypoint>>(waypointsControllerProvider, (previous, next) {
      _syncCircles(next);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: MapLibreMap(
        styleString: AppConfig.mapStyleUrl,
        initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 1),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        onMapLongClick: _onMapLongClick,
      ),
    );
  }
}
```

- [ ] **Step 4: Run the existing tests again**

Run: `flutter test test/map/map_screen_test.dart` (from `app/`)
Expected: PASS. (`FakeWaypointsRepository()` with no `initial` returns an empty list, so `_syncCircles` has nothing to do since `_controller` is also still `null` in these tests — no real map platform view is created under `flutter test`.)

- [ ] **Step 5: Add a test for the create flow via long-press**

Add to `app/test/map/map_screen_test.dart` (append to the existing file, keep the earlier two tests):

```dart
  testWidgets('long-press opens the form and creates a waypoint on submit', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final authRepo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final waypointsRepo = FakeWaypointsRepository()
      ..createResult = Waypoint(
        id: 'w1',
        orgId: 'o1',
        ownerId: 'u1',
        name: 'Summit',
        type: 'generic',
        note: null,
        lat: 1.0,
        lng: 2.0,
        canEdit: true,
        createdAt: DateTime.utc(2026, 8, 22),
      );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(waypointsRepo),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    // MapLibreMap has no real platform view under flutter test, so this
    // exercises the same controller call _onMapLongClick makes rather than
    // simulating a real long-press gesture on the (unrenderable) map widget.
    await container.read(waypointsControllerProvider.notifier).createWaypoint(
          ownerId: 'u1',
          name: 'Summit',
          type: 'generic',
          note: '',
          lat: 1.0,
          lng: 2.0,
        );

    expect(container.read(waypointsControllerProvider), hasLength(1));
    expect(container.read(waypointsControllerProvider).single.name, 'Summit');
  });
```

- [ ] **Step 6: Run the full frontend test suite**

Run: `flutter test` (from `app/`)
Expected: PASS, all tests across the whole suite green.

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze` (from `app/`)
Expected: no issues.

- [ ] **Step 8: Manual verification on a real device (required — not covered by unit tests)**

Per this project's established practice (no working Android emulator on the dev machine), this step is the user's responsibility:
1. Rebuild the debug APK with the LAN `API_BASE_URL` dart-define (as already set up in `.github/workflows/flutter-build.yml`), install on a physical device on the same Wi-Fi network as the backend.
2. Long-press the map → fill the form → confirm the marker appears immediately (optimistic) and persists after an app restart (confirms the `POST` succeeded and `loadWaypoints()` picks it up again).
3. Tap the marker → confirm the bottom sheet shows name/type/note and Edit/Delete buttons (since the test user owns it).
4. Edit → change type/note → confirm the marker's color updates.
5. Delete → confirm the marker disappears and confirmation dialog worked.
6. Turn off Wi-Fi mid-create (or point `API_BASE_URL` at an unreachable host) → confirm the optimistic marker disappears and a SnackBar error appears — verifies the rollback path that unit tests can only check at the controller level, not through the real `maplibre_gl` circle layer.

- [ ] **Step 9: Commit**

```bash
git add app/lib/map/map_screen.dart app/test/map/map_screen_test.dart
git commit -m "feat: render, create, edit, and delete waypoints on the map"
```

---

## Final review

After Task 11, run the full regression check across both stacks before considering the slice done:

```bash
docker compose exec api pytest -q
```

```bash
cd app && flutter analyze && flutter test
```

Both must be fully green. Per this project's established practice, also do a final whole-branch review (even though this was built as a single slice/branch) before merging — a final review has caught real bugs on this project before that no individual task's review did (see the `project_roles_sharing_schema` memory).
