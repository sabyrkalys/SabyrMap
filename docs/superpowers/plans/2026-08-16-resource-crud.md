# Resource CRUD (Waypoints, Tracks, Sharing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the existing waypoint/track/sharing data model over HTTP — `POST/GET/PATCH/DELETE /waypoints[/{id}]`, the same shape under `/tracks`, and `POST/GET /resources/{id}/shares` + `DELETE /resources/{id}/shares/{share_id}` for sharing — so a client can actually create, browse, edit, delete, and share map resources instead of only the maintainers being able to via a Python shell.

**Architecture:** A new GeoJSON⇄PostGIS conversion layer (`app/schemas/geometry.py`) sits under two nearly-identical CRUD routers (`waypoints.py`, `tracks.py`), each delegating to the existing `create_waypoint`/`create_track` services and the existing `can_view_resource` plus a new `can_edit_resource` authorization function. A third router (`shares.py`) manages `ResourceShare` rows directly, keyed on `resources.id` so it works identically for either resource type. All three routers sit behind the existing `get_current_user` auth dependency.

**Tech Stack:** FastAPI, Pydantic v2, SQLAlchemy 2.0, GeoAlchemy2 + Shapely (already in `requirements.txt`, no new dependencies).

**Spec:** `docs/superpowers/specs/2026-08-15-resource-crud-design.md`

## Global Constraints

- Geometry over the wire is GeoJSON (`{"type": "Point", "coordinates": [lon, lat]}` / `{"type": "LineString", "coordinates": [[lon, lat], ...]}`). A `/waypoints` request with a non-`Point` geometry (or `/tracks` with non-`LineString`) is a `422`.
- `GET .../{id}` on a resource that exists but the caller cannot view returns `403`, not `404`. A resource that does not exist or is soft-deleted returns `404`.
- `can_edit_resource(db, user, resource) -> bool`: `True` iff resource not soft-deleted AND (`user.id == resource.owner_id` OR a `ResourceShare` with `permission=EDIT` covers this user/org). Organization `owner`/`admin` roles do **not** get automatic edit rights — only `can_view_resource` grants them oversight. This is the one deliberate behavioral difference from `can_view_resource`.
- `PATCH` is partial — only supplied fields (`name` and/or `geom`) change.
- `DELETE` is soft delete — sets `resources.deleted_at`, never removes rows.
- List endpoints (`GET /waypoints`, `GET /tracks`) return everything the caller can view under `can_view_resource`, paginated with optional `limit` (default 50, max 200) and `offset` (default 0) query params.
- Sharing management (`POST`/`GET`/`DELETE` on `/resources/{id}/shares`) requires `can_edit_resource` on the target resource — the same rule as editing the resource itself.
- A share with `scope=user` requires `shared_with_user_id`; a share with `scope=organization` must omit it — violating this is `422`. `shared_with_user_id` must belong to the resource's own organization, or `422`.
- All queries filter `deleted_at IS NULL` (resources and users).

---

## File Structure

```
api/app/
  schemas/
    geometry.py     # GeoJSON <-> PostGIS conversion (new)
    waypoints.py    # Waypoint request/response schemas (new)
    tracks.py       # Track request/response schemas (new)
    shares.py       # Share request/response schemas (new)
  services/
    authorization.py  # + can_edit_resource (modified)
  routers/
    waypoints.py    # /waypoints CRUD (new)
    tracks.py       # /tracks CRUD (new)
    shares.py       # /resources/{id}/shares (new)
  main.py           # + 3 router mounts (modified)
api/tests/
  test_geometry_schemas.py     # new
  test_authorization_service.py  # + can_edit_resource tests (modified)
  test_waypoints_api.py        # new
  test_tracks_api.py           # new
  test_shares_api.py           # new
```

---

### Task 1: GeoJSON ⇄ PostGIS conversion schemas

**Files:**
- Create: `api/app/schemas/geometry.py`
- Test: `api/tests/test_geometry_schemas.py` (create)

**Interfaces:**
- Produces: `GeoJSONPoint(BaseModel)` (`type: Literal["Point"]`, `coordinates: tuple[float, float]`), `GeoJSONLineString(BaseModel)` (`type: Literal["LineString"]`, `coordinates: list[tuple[float, float]]`, min 2 points), `point_to_geojson(geom) -> GeoJSONPoint`, `geojson_to_point(geo: GeoJSONPoint) -> WKBElement`, `linestring_to_geojson(geom) -> GeoJSONLineString`, `geojson_to_linestring(geo: GeoJSONLineString) -> WKBElement`.

These conversions do not touch the database (`geoalchemy2.shape.from_shape`/`to_shape` operate on WKB bytes in pure Python), so this task's tests need no `db_session` fixture.

- [ ] **Step 1: Write the failing tests**

Create `api/tests/test_geometry_schemas.py`:

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_geometry_schemas.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.schemas.geometry'`.

- [ ] **Step 3: Implement**

Create `api/app/schemas/geometry.py`:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd api && pytest tests/test_geometry_schemas.py -v`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add api/app/schemas/geometry.py api/tests/test_geometry_schemas.py
git commit -m "feat: add GeoJSON <-> PostGIS conversion schemas"
```

---

### Task 2: `can_edit_resource` authorization rule

**Files:**
- Modify: `api/app/services/authorization.py`
- Test: `api/tests/test_authorization_service.py` (modify)

**Interfaces:**
- Consumes: `Resource`, `ResourceShare`, `User`, `Permission`, `ShareScope` (existing models/enums)
- Produces: `can_edit_resource(db: Session, user: User, resource: Resource) -> bool`

- [ ] **Step 1: Write the failing tests**

Append to `api/tests/test_authorization_service.py` (the file already imports `Permission, ResourceType, Role, ShareScope` and has a `_setup` helper — reuse both):

```python
from app.services.authorization import can_edit_resource  # add to the existing import line


def test_owner_can_edit_own_resource(db_session):
    org, (owner,) = _setup(db_session, roles=(Role.MEMBER,))
    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_edit_resource(db_session, owner, resource) is True


def test_org_admin_cannot_edit_others_resource_without_share(db_session):
    org, (creator, admin) = _setup(db_session, roles=(Role.MEMBER, Role.ADMIN))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_edit_resource(db_session, admin, resource) is False


def test_user_scope_edit_share_grants_edit(db_session):
    org, (creator, editor) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=editor.id,
        scope=ShareScope.USER, permission=Permission.EDIT, created_by=creator.id,
    ))
    db_session.flush()

    assert can_edit_resource(db_session, editor, resource) is True


def test_organization_scope_edit_share_grants_edit_to_any_member(db_session):
    org, (creator, other_member) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=None,
        scope=ShareScope.ORGANIZATION, permission=Permission.EDIT, created_by=creator.id,
    ))
    db_session.flush()

    assert can_edit_resource(db_session, other_member, resource) is True


def test_view_only_share_does_not_grant_edit(db_session):
    org, (creator, viewer) = _setup(db_session, roles=(Role.MEMBER, Role.MEMBER))
    resource = Resource(org_id=org.id, owner_id=creator.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()
    db_session.add(ResourceShare(
        resource_id=resource.id, shared_with_user_id=viewer.id,
        scope=ShareScope.USER, permission=Permission.VIEW, created_by=creator.id,
    ))
    db_session.flush()

    assert can_edit_resource(db_session, viewer, resource) is False


def test_deleted_resource_cannot_be_edited(db_session):
    from datetime import datetime, timezone

    org, (owner,) = _setup(db_session, roles=(Role.OWNER,))
    resource = Resource(
        org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT,
        deleted_at=datetime.now(timezone.utc),
    )
    db_session.add(resource)
    db_session.flush()

    assert can_edit_resource(db_session, owner, resource) is False


def test_soft_deleted_user_cannot_edit(db_session):
    from datetime import datetime, timezone

    org, (owner,) = _setup(db_session, roles=(Role.OWNER,))
    owner.deleted_at = datetime.now(timezone.utc)
    db_session.flush()
    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    assert can_edit_resource(db_session, owner, resource) is False
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_authorization_service.py -v`
Expected: the 7 new tests FAIL with `ImportError: cannot import name 'can_edit_resource'`. The existing `can_view_resource` tests still PASS.

- [ ] **Step 3: Implement**

In `api/app/services/authorization.py`, add this import to the existing `from app.models.enums import Role, ShareScope` line (making it `from app.models.enums import Permission, Role, ShareScope`), and append below `can_view_resource`:

```python
def can_edit_resource(db: Session, user: User, resource: Resource) -> bool:
    if user.deleted_at is not None:
        return False
    if resource.deleted_at is not None:
        return False
    if resource.org_id != user.org_id:
        return False
    if resource.owner_id == user.id:
        return True

    share_exists = (
        db.query(ResourceShare)
        .filter(
            ResourceShare.resource_id == resource.id,
            ResourceShare.permission == Permission.EDIT,
            or_(
                ResourceShare.scope == ShareScope.ORGANIZATION,
                and_(
                    ResourceShare.scope == ShareScope.USER,
                    ResourceShare.shared_with_user_id == user.id,
                ),
            ),
        )
        .first()
    )
    return share_exists is not None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd api && pytest tests/test_authorization_service.py -v`
Expected: all 17 tests (10 existing + 7 new) PASS.

- [ ] **Step 5: Commit**

```bash
git add api/app/services/authorization.py api/tests/test_authorization_service.py
git commit -m "feat: add can_edit_resource authorization rule"
```

---

### Task 3: Waypoint create/list/get endpoints

**Files:**
- Create: `api/app/schemas/waypoints.py`
- Create: `api/app/routers/waypoints.py`
- Modify: `api/app/main.py`
- Test: `api/tests/test_waypoints_api.py` (create)

**Interfaces:**
- Consumes: `create_waypoint` (existing, `app.services.resources`), `can_view_resource` (existing), `get_current_user` (existing, `app.dependencies`), `point_to_geojson`/`geojson_to_point` (Task 1)
- Produces: `WaypointCreateRequest(name, geom: GeoJSONPoint)`, `WaypointUpdateRequest(name?, geom?: GeoJSONPoint)`, `WaypointResponse(id, org_id, owner_id, name, geom, created_at)`, `WaypointListResponse(items, limit, offset)`; `router` (FastAPI `APIRouter`, prefix `/waypoints`) mounted in `main.py`. `WaypointUpdateRequest` is defined now for Task 4 to use without touching this file's schema again.

- [ ] **Step 1: Write the failing tests**

Create `api/tests/test_waypoints_api.py`:

```python
def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_create_and_get_waypoint(client):
    headers = _register(client, "waypoint-create@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Trailhead", "geom": {"type": "Point", "coordinates": [7.6, 45.9]}},
        headers=headers,
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Trailhead"
    assert body["geom"] == {"type": "Point", "coordinates": [7.6, 45.9]}

    get_response = client.get(f"/waypoints/{body['id']}", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["id"] == body["id"]


def test_list_waypoints_returns_created(client):
    headers = _register(client, "waypoint-list@example.test")
    client.post(
        "/waypoints",
        json={"name": "A", "geom": {"type": "Point", "coordinates": [1.0, 2.0]}},
        headers=headers,
    )
    response = client.get("/waypoints", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 50
    assert body["offset"] == 0
    assert any(item["name"] == "A" for item in body["items"])


def test_get_waypoint_not_found(client):
    import uuid

    headers = _register(client, "waypoint-404@example.test")
    response = client.get(f"/waypoints/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_get_waypoint_forbidden_for_other_org(client):
    owner_headers = _register(client, "waypoint-owner-a@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Secret", "geom": {"type": "Point", "coordinates": [3.0, 4.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-owner-b@example.test")
    response = client.get(f"/waypoints/{waypoint_id}", headers=other_headers)
    assert response.status_code == 403


def test_create_waypoint_rejects_wrong_geometry_type(client):
    headers = _register(client, "waypoint-badgeom@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Bad",
            "geom": {"type": "LineString", "coordinates": [[1.0, 2.0], [3.0, 4.0]]},
        },
        headers=headers,
    )
    assert response.status_code == 422


def test_list_waypoints_pagination(client):
    headers = _register(client, "waypoint-page@example.test")
    for i in range(3):
        client.post(
            "/waypoints",
            json={"name": f"P{i}", "geom": {"type": "Point", "coordinates": [float(i), float(i)]}},
            headers=headers,
        )
    response = client.get("/waypoints?limit=2&offset=1", headers=headers)
    body = response.json()
    assert len(body["items"]) == 2
    assert body["limit"] == 2
    assert body["offset"] == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_waypoints_api.py -v`
Expected: FAIL — `/waypoints` doesn't exist yet (404s / import errors).

- [ ] **Step 3: Implement the schemas**

Create `api/app/schemas/waypoints.py`:

```python
import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.geometry import GeoJSONPoint


class WaypointCreateRequest(BaseModel):
    name: str
    geom: GeoJSONPoint


class WaypointUpdateRequest(BaseModel):
    name: str | None = None
    geom: GeoJSONPoint | None = None


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    geom: GeoJSONPoint
    created_at: datetime


class WaypointListResponse(BaseModel):
    items: list[WaypointResponse]
    limit: int
    offset: int
```

- [ ] **Step 4: Implement the router**

Create `api/app/routers/waypoints.py`:

```python
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.user import User
from app.models.waypoint import Waypoint
from app.schemas.geometry import geojson_to_point, point_to_geojson
from app.schemas.waypoints import WaypointCreateRequest, WaypointListResponse, WaypointResponse
from app.services.authorization import can_view_resource
from app.services.resources import create_waypoint

router = APIRouter(prefix="/waypoints", tags=["waypoints"])


def _to_response(resource: Resource, waypoint: Waypoint) -> WaypointResponse:
    return WaypointResponse(
        id=waypoint.id,
        org_id=resource.org_id,
        owner_id=resource.owner_id,
        name=waypoint.name,
        geom=point_to_geojson(waypoint.geom),
        created_at=resource.created_at,
    )


def _get_resource_and_waypoint(db: Session, waypoint_id: uuid.UUID) -> tuple[Resource, Waypoint]:
    resource = (
        db.query(Resource)
        .filter(Resource.id == waypoint_id, Resource.deleted_at.is_(None))
        .first()
    )
    waypoint = db.get(Waypoint, waypoint_id) if resource is not None else None
    if resource is None or waypoint is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Waypoint not found")
    return resource, waypoint


@router.post("", response_model=WaypointResponse, status_code=status.HTTP_201_CREATED)
def create(
    payload: WaypointCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    waypoint = create_waypoint(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_point(payload.geom),
    )
    resource = db.get(Resource, waypoint.id)
    return _to_response(resource, waypoint)


@router.get("", response_model=WaypointListResponse)
def list_waypoints(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resources = (
        db.query(Resource)
        .filter(Resource.resource_type == ResourceType.WAYPOINT, Resource.deleted_at.is_(None))
        .order_by(Resource.created_at)
        .all()
    )
    visible = [r for r in resources if can_view_resource(db, current_user, r)]
    page = visible[offset : offset + limit]
    items = [_to_response(resource, db.get(Waypoint, resource.id)) for resource in page]
    return WaypointListResponse(items=items, limit=limit, offset=offset)


@router.get("/{waypoint_id}", response_model=WaypointResponse)
def get_waypoint(
    waypoint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_view_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this waypoint")
    return _to_response(resource, waypoint)
```

- [ ] **Step 5: Wire the router into the app**

In `api/app/main.py`, replace the whole file with:

```python
from fastapi import FastAPI

from app.routers.auth import router as auth_router
from app.routers.waypoints import router as waypoints_router

app = FastAPI(title="AlpineQuest SaaS API")
app.include_router(auth_router)
app.include_router(waypoints_router)


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd api && pytest tests/test_waypoints_api.py -v`
Expected: all 6 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add api/app/schemas/waypoints.py api/app/routers/waypoints.py api/app/main.py api/tests/test_waypoints_api.py
git commit -m "feat: add waypoint create/list/get endpoints"
```

---

### Task 4: Waypoint update/delete endpoints

**Files:**
- Modify: `api/app/routers/waypoints.py`
- Test: `api/tests/test_waypoints_api.py` (modify)

**Interfaces:**
- Consumes: `can_edit_resource` (Task 2), `WaypointUpdateRequest` (Task 3)
- Produces: `PATCH /waypoints/{id}`, `DELETE /waypoints/{id}` routes on the existing `router`

- [ ] **Step 1: Write the failing tests**

Append to `api/tests/test_waypoints_api.py`:

```python
def test_update_waypoint_name_only(client):
    headers = _register(client, "waypoint-update@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Old", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"name": "New"}, headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "New"
    assert body["geom"] == {"type": "Point", "coordinates": [1.0, 1.0]}


def test_update_waypoint_forbidden_without_edit_access(client):
    owner_headers = _register(client, "waypoint-edit-owner@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Mine", "geom": {"type": "Point", "coordinates": [2.0, 2.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-edit-other@example.test")
    response = client.patch(f"/waypoints/{waypoint_id}", json={"name": "Hacked"}, headers=other_headers)
    assert response.status_code == 403


def test_delete_waypoint_soft_deletes(client):
    headers = _register(client, "waypoint-delete@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Gone", "geom": {"type": "Point", "coordinates": [5.0, 5.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    delete_response = client.delete(f"/waypoints/{waypoint_id}", headers=headers)
    assert delete_response.status_code == 204

    get_response = client.get(f"/waypoints/{waypoint_id}", headers=headers)
    assert get_response.status_code == 404

    list_response = client.get("/waypoints", headers=headers)
    assert all(item["id"] != waypoint_id for item in list_response.json()["items"])


def test_delete_waypoint_forbidden_without_edit_access(client):
    owner_headers = _register(client, "waypoint-del-owner@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "Protected", "geom": {"type": "Point", "coordinates": [6.0, 6.0]}},
        headers=owner_headers,
    )
    waypoint_id = create_response.json()["id"]

    other_headers = _register(client, "waypoint-del-other@example.test")
    response = client.delete(f"/waypoints/{waypoint_id}", headers=other_headers)
    assert response.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_waypoints_api.py -v`
Expected: the 4 new tests FAIL (405 Method Not Allowed — PATCH/DELETE not registered). The 6 existing tests still PASS.

- [ ] **Step 3: Implement**

In `api/app/routers/waypoints.py`, add these imports (`datetime, timezone` and `WaypointUpdateRequest`, `can_edit_resource`) and the two new routes at the end of the file:

```python
from datetime import datetime, timezone
```

Update the `app.schemas.waypoints` import line to:

```python
from app.schemas.waypoints import WaypointCreateRequest, WaypointListResponse, WaypointResponse, WaypointUpdateRequest
```

Update the `app.services.authorization` import line to:

```python
from app.services.authorization import can_edit_resource, can_view_resource
```

Append at the end of the file:

```python
@router.patch("/{waypoint_id}", response_model=WaypointResponse)
def update_waypoint(
    waypoint_id: uuid.UUID,
    payload: WaypointUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to edit this waypoint")

    if payload.name is not None:
        waypoint.name = payload.name
    if payload.geom is not None:
        waypoint.geom = geojson_to_point(payload.geom)
    db.flush()
    return _to_response(resource, waypoint)


@router.delete("/{waypoint_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_waypoint(
    waypoint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, waypoint = _get_resource_and_waypoint(db, waypoint_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to delete this waypoint")

    resource.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd api && pytest tests/test_waypoints_api.py -v`
Expected: all 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add api/app/routers/waypoints.py api/tests/test_waypoints_api.py
git commit -m "feat: add waypoint update/delete endpoints"
```

---

### Task 5: Track CRUD (full)

**Files:**
- Create: `api/app/schemas/tracks.py`
- Create: `api/app/routers/tracks.py`
- Modify: `api/app/main.py`
- Test: `api/tests/test_tracks_api.py` (create)

**Interfaces:**
- Consumes: `create_track` (existing, `app.services.resources`), `can_view_resource`/`can_edit_resource` (existing/Task 2), `get_current_user` (existing), `linestring_to_geojson`/`geojson_to_linestring` (Task 1)
- Produces: `TrackCreateRequest(name, geom: GeoJSONLineString)`, `TrackUpdateRequest(name?, geom?: GeoJSONLineString)`, `TrackResponse(id, org_id, owner_id, name, geom, created_at)`, `TrackListResponse(items, limit, offset)`; `router` (prefix `/tracks`) mounted in `main.py`

This task mirrors Tasks 3+4's waypoint pattern exactly, substituting `LineString`/`Track`/`create_track` — full CRUD lands in one task since the pattern is already proven.

- [ ] **Step 1: Write the failing tests**

Create `api/tests/test_tracks_api.py`:

```python
def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


_LINE_A = {"type": "LineString", "coordinates": [[7.6, 45.9], [7.7, 46.0], [7.8, 46.05]]}
_LINE_B = {"type": "LineString", "coordinates": [[1.0, 1.0], [2.0, 2.0]]}


def test_create_and_get_track(client):
    headers = _register(client, "track-create@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Ridge Loop", "geom": _LINE_A}, headers=headers
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["name"] == "Ridge Loop"
    assert body["geom"] == _LINE_A

    get_response = client.get(f"/tracks/{body['id']}", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["id"] == body["id"]


def test_list_tracks_returns_created(client):
    headers = _register(client, "track-list@example.test")
    client.post("/tracks", json={"name": "A", "geom": _LINE_B}, headers=headers)
    response = client.get("/tracks", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 50
    assert body["offset"] == 0
    assert any(item["name"] == "A" for item in body["items"])


def test_get_track_not_found(client):
    import uuid

    headers = _register(client, "track-404@example.test")
    response = client.get(f"/tracks/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_get_track_forbidden_for_other_org(client):
    owner_headers = _register(client, "track-owner-a@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Secret", "geom": _LINE_A}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-owner-b@example.test")
    response = client.get(f"/tracks/{track_id}", headers=other_headers)
    assert response.status_code == 403


def test_create_track_rejects_wrong_geometry_type(client):
    headers = _register(client, "track-badgeom@example.test")
    response = client.post(
        "/tracks",
        json={"name": "Bad", "geom": {"type": "Point", "coordinates": [1.0, 2.0]}},
        headers=headers,
    )
    assert response.status_code == 422


def test_create_track_rejects_single_point_linestring(client):
    headers = _register(client, "track-shortline@example.test")
    response = client.post(
        "/tracks",
        json={"name": "TooShort", "geom": {"type": "LineString", "coordinates": [[1.0, 2.0]]}},
        headers=headers,
    )
    assert response.status_code == 422


def test_list_tracks_pagination(client):
    headers = _register(client, "track-page@example.test")
    for i in range(3):
        client.post(
            "/tracks",
            json={"name": f"T{i}", "geom": {"type": "LineString", "coordinates": [[float(i), float(i)], [float(i) + 1, float(i) + 1]]}},
            headers=headers,
        )
    response = client.get("/tracks?limit=2&offset=1", headers=headers)
    body = response.json()
    assert len(body["items"]) == 2
    assert body["limit"] == 2
    assert body["offset"] == 1


def test_update_track_name_only(client):
    headers = _register(client, "track-update@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Old", "geom": _LINE_B}, headers=headers
    )
    track_id = create_response.json()["id"]

    response = client.patch(f"/tracks/{track_id}", json={"name": "New"}, headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "New"
    assert body["geom"] == _LINE_B


def test_update_track_forbidden_without_edit_access(client):
    owner_headers = _register(client, "track-edit-owner@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Mine", "geom": _LINE_B}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-edit-other@example.test")
    response = client.patch(f"/tracks/{track_id}", json={"name": "Hacked"}, headers=other_headers)
    assert response.status_code == 403


def test_delete_track_soft_deletes(client):
    headers = _register(client, "track-delete@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Gone", "geom": _LINE_B}, headers=headers
    )
    track_id = create_response.json()["id"]

    delete_response = client.delete(f"/tracks/{track_id}", headers=headers)
    assert delete_response.status_code == 204

    get_response = client.get(f"/tracks/{track_id}", headers=headers)
    assert get_response.status_code == 404

    list_response = client.get("/tracks", headers=headers)
    assert all(item["id"] != track_id for item in list_response.json()["items"])


def test_delete_track_forbidden_without_edit_access(client):
    owner_headers = _register(client, "track-del-owner@example.test")
    create_response = client.post(
        "/tracks", json={"name": "Protected", "geom": _LINE_B}, headers=owner_headers
    )
    track_id = create_response.json()["id"]

    other_headers = _register(client, "track-del-other@example.test")
    response = client.delete(f"/tracks/{track_id}", headers=other_headers)
    assert response.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_tracks_api.py -v`
Expected: FAIL — `/tracks` doesn't exist yet.

- [ ] **Step 3: Implement the schemas**

Create `api/app/schemas/tracks.py`:

```python
import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.geometry import GeoJSONLineString


class TrackCreateRequest(BaseModel):
    name: str
    geom: GeoJSONLineString


class TrackUpdateRequest(BaseModel):
    name: str | None = None
    geom: GeoJSONLineString | None = None


class TrackResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    geom: GeoJSONLineString
    created_at: datetime


class TrackListResponse(BaseModel):
    items: list[TrackResponse]
    limit: int
    offset: int
```

- [ ] **Step 4: Implement the router**

Create `api/app/routers/tracks.py`:

```python
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.enums import ResourceType
from app.models.resource import Resource
from app.models.track import Track
from app.models.user import User
from app.schemas.geometry import geojson_to_linestring, linestring_to_geojson
from app.schemas.tracks import TrackCreateRequest, TrackListResponse, TrackResponse, TrackUpdateRequest
from app.services.authorization import can_edit_resource, can_view_resource
from app.services.resources import create_track

router = APIRouter(prefix="/tracks", tags=["tracks"])


def _to_response(resource: Resource, track: Track) -> TrackResponse:
    return TrackResponse(
        id=track.id,
        org_id=resource.org_id,
        owner_id=resource.owner_id,
        name=track.name,
        geom=linestring_to_geojson(track.geom),
        created_at=resource.created_at,
    )


def _get_resource_and_track(db: Session, track_id: uuid.UUID) -> tuple[Resource, Track]:
    resource = (
        db.query(Resource)
        .filter(Resource.id == track_id, Resource.deleted_at.is_(None))
        .first()
    )
    track = db.get(Track, track_id) if resource is not None else None
    if resource is None or track is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Track not found")
    return resource, track


@router.post("", response_model=TrackResponse, status_code=status.HTTP_201_CREATED)
def create(
    payload: TrackCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    track = create_track(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_linestring(payload.geom),
    )
    resource = db.get(Resource, track.id)
    return _to_response(resource, track)


@router.get("", response_model=TrackListResponse)
def list_tracks(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resources = (
        db.query(Resource)
        .filter(Resource.resource_type == ResourceType.TRACK, Resource.deleted_at.is_(None))
        .order_by(Resource.created_at)
        .all()
    )
    visible = [r for r in resources if can_view_resource(db, current_user, r)]
    page = visible[offset : offset + limit]
    items = [_to_response(resource, db.get(Track, resource.id)) for resource in page]
    return TrackListResponse(items=items, limit=limit, offset=offset)


@router.get("/{track_id}", response_model=TrackResponse)
def get_track(
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_view_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this track")
    return _to_response(resource, track)


@router.patch("/{track_id}", response_model=TrackResponse)
def update_track(
    track_id: uuid.UUID,
    payload: TrackUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to edit this track")

    if payload.name is not None:
        track.name = payload.name
    if payload.geom is not None:
        track.geom = geojson_to_linestring(payload.geom)
    db.flush()
    return _to_response(resource, track)


@router.delete("/{track_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_track(
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource, track = _get_resource_and_track(db, track_id)
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to delete this track")

    resource.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return None
```

- [ ] **Step 5: Wire the router into the app**

In `api/app/main.py`, add the import and mount:

```python
from fastapi import FastAPI

from app.routers.auth import router as auth_router
from app.routers.tracks import router as tracks_router
from app.routers.waypoints import router as waypoints_router

app = FastAPI(title="AlpineQuest SaaS API")
app.include_router(auth_router)
app.include_router(waypoints_router)
app.include_router(tracks_router)


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd api && pytest tests/test_tracks_api.py -v`
Expected: all 11 tests PASS.

- [ ] **Step 7: Run the full suite**

Run: `cd api && pytest -v`
Expected: all tests PASS, no regressions.

- [ ] **Step 8: Commit**

```bash
git add api/app/schemas/tracks.py api/app/routers/tracks.py api/app/main.py api/tests/test_tracks_api.py
git commit -m "feat: add track CRUD endpoints"
```

---

### Task 6: Resource sharing endpoints

**Files:**
- Create: `api/app/schemas/shares.py`
- Create: `api/app/routers/shares.py`
- Modify: `api/app/main.py`
- Test: `api/tests/test_shares_api.py` (create)

**Interfaces:**
- Consumes: `can_edit_resource` (Task 2), `ResourceShare`/`Permission`/`ShareScope` (existing models), `get_current_user` (existing)
- Produces: `ShareCreateRequest(scope, permission, shared_with_user_id?)`, `ShareResponse(id, resource_id, scope, permission, shared_with_user_id, created_by, created_at)`, `ShareListResponse(items)`; `router` (prefix `/resources`) mounted in `main.py`

- [ ] **Step 1: Write the failing tests**

Create `api/tests/test_shares_api.py`:

```python
import uuid

from app.models.enums import Role
from app.models.organization import Organization
from app.models.user import User
from app.services.auth import create_access_token


def _register(client, email, password="s3cret-pass"):
    response = client.post("/auth/register", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _create_waypoint(client, headers, name="Shared Point"):
    response = client.post(
        "/waypoints",
        json={"name": name, "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    return response.json()["id"]


def _add_org_member(db_session, org_id, email, role=Role.MEMBER):
    user = User(org_id=org_id, email=email, password_hash="not-a-real-hash", role=role)
    db_session.add(user)
    db_session.flush()
    return user


def _auth_headers_for(user):
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def test_owner_can_create_organization_scope_share(client):
    headers = _register(client, "share-owner@example.test")
    waypoint_id = _create_waypoint(client, headers)

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["scope"] == "organization"
    assert body["shared_with_user_id"] is None


def test_edit_shared_user_can_also_create_shares(client, db_session):
    owner_headers = _register(client, "share-owner-2@example.test")
    waypoint_id = _create_waypoint(client, owner_headers)

    owner = db_session.query(User).filter_by(email="share-owner-2@example.test").one()
    editor = _add_org_member(db_session, owner.org_id, "share-editor@example.test")

    grant_response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "edit", "shared_with_user_id": str(editor.id)},
        headers=owner_headers,
    )
    assert grant_response.status_code == 201

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=_auth_headers_for(editor),
    )
    assert response.status_code == 201


def test_view_shared_user_cannot_create_shares(client, db_session):
    owner_headers = _register(client, "share-owner-3@example.test")
    waypoint_id = _create_waypoint(client, owner_headers)

    owner = db_session.query(User).filter_by(email="share-owner-3@example.test").one()
    viewer = _add_org_member(db_session, owner.org_id, "share-viewer@example.test")

    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(viewer.id)},
        headers=owner_headers,
    )

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=_auth_headers_for(viewer),
    )
    assert response.status_code == 403


def test_list_shares(client):
    headers = _register(client, "share-owner-4@example.test")
    waypoint_id = _create_waypoint(client, headers)
    client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )

    response = client.get(f"/resources/{waypoint_id}/shares", headers=headers)
    assert response.status_code == 200
    assert len(response.json()["items"]) == 1


def test_delete_share(client):
    headers = _register(client, "share-owner-5@example.test")
    waypoint_id = _create_waypoint(client, headers)
    create_response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    share_id = create_response.json()["id"]

    delete_response = client.delete(f"/resources/{waypoint_id}/shares/{share_id}", headers=headers)
    assert delete_response.status_code == 204

    list_response = client.get(f"/resources/{waypoint_id}/shares", headers=headers)
    assert list_response.json()["items"] == []


def test_share_to_user_outside_org_rejected(client, db_session):
    headers = _register(client, "share-owner-6@example.test")
    waypoint_id = _create_waypoint(client, headers)

    other_org = Organization(name="Other Org", plan="personal")
    db_session.add(other_org)
    db_session.flush()
    outsider = _add_org_member(db_session, other_org.id, "outsider@example.test")

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "user", "permission": "view", "shared_with_user_id": str(outsider.id)},
        headers=headers,
    )
    assert response.status_code == 422


def test_share_scope_target_mismatch_rejected(client):
    headers = _register(client, "share-owner-7@example.test")
    waypoint_id = _create_waypoint(client, headers)

    response = client.post(
        f"/resources/{waypoint_id}/shares",
        json={"scope": "organization", "permission": "view", "shared_with_user_id": str(uuid.uuid4())},
        headers=headers,
    )
    assert response.status_code == 422


def test_create_share_on_nonexistent_resource_404(client):
    headers = _register(client, "share-owner-8@example.test")
    response = client.post(
        f"/resources/{uuid.uuid4()}/shares",
        json={"scope": "organization", "permission": "view"},
        headers=headers,
    )
    assert response.status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd api && pytest tests/test_shares_api.py -v`
Expected: FAIL — `/resources/{id}/shares` doesn't exist yet.

- [ ] **Step 3: Implement the schemas**

Create `api/app/schemas/shares.py`:

```python
import uuid
from datetime import datetime

from pydantic import BaseModel, field_validator

from app.models.enums import Permission, ShareScope


class ShareCreateRequest(BaseModel):
    scope: ShareScope
    permission: Permission
    shared_with_user_id: uuid.UUID | None = None

    @field_validator("shared_with_user_id")
    @classmethod
    def _validate_target(cls, v: uuid.UUID | None, info) -> uuid.UUID | None:
        scope = info.data.get("scope")
        if scope == ShareScope.USER and v is None:
            raise ValueError("shared_with_user_id is required when scope is 'user'")
        if scope == ShareScope.ORGANIZATION and v is not None:
            raise ValueError("shared_with_user_id must be omitted when scope is 'organization'")
        return v


class ShareResponse(BaseModel):
    id: uuid.UUID
    resource_id: uuid.UUID
    scope: ShareScope
    permission: Permission
    shared_with_user_id: uuid.UUID | None
    created_by: uuid.UUID
    created_at: datetime


class ShareListResponse(BaseModel):
    items: list[ShareResponse]
```

- [ ] **Step 4: Implement the router**

Create `api/app/routers/shares.py`:

```python
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.resource import Resource
from app.models.resource_share import ResourceShare
from app.models.user import User
from app.schemas.shares import ShareCreateRequest, ShareListResponse, ShareResponse
from app.services.authorization import can_edit_resource

router = APIRouter(prefix="/resources", tags=["shares"])


def _get_resource(db: Session, resource_id: uuid.UUID) -> Resource:
    resource = (
        db.query(Resource)
        .filter(Resource.id == resource_id, Resource.deleted_at.is_(None))
        .first()
    )
    if resource is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Resource not found")
    return resource


def _require_edit(db: Session, current_user: User, resource: Resource) -> None:
    if not can_edit_resource(db, current_user, resource):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to manage sharing for this resource",
        )


def _to_response(share: ResourceShare) -> ShareResponse:
    return ShareResponse(
        id=share.id,
        resource_id=share.resource_id,
        scope=share.scope,
        permission=share.permission,
        shared_with_user_id=share.shared_with_user_id,
        created_by=share.created_by,
        created_at=share.created_at,
    )


@router.post("/{resource_id}/shares", response_model=ShareResponse, status_code=status.HTTP_201_CREATED)
def create_share(
    resource_id: uuid.UUID,
    payload: ShareCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    if payload.shared_with_user_id is not None:
        target = (
            db.query(User)
            .filter(User.id == payload.shared_with_user_id, User.deleted_at.is_(None))
            .first()
        )
        if target is None or target.org_id != resource.org_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="shared_with_user_id must belong to the resource's organization",
            )

    share = ResourceShare(
        resource_id=resource.id,
        shared_with_user_id=payload.shared_with_user_id,
        scope=payload.scope,
        permission=payload.permission,
        created_by=current_user.id,
    )
    db.add(share)
    db.flush()
    return _to_response(share)


@router.get("/{resource_id}/shares", response_model=ShareListResponse)
def list_shares(
    resource_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    shares = db.query(ResourceShare).filter(ResourceShare.resource_id == resource.id).all()
    return ShareListResponse(items=[_to_response(s) for s in shares])


@router.delete("/{resource_id}/shares/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_share(
    resource_id: uuid.UUID,
    share_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    resource = _get_resource(db, resource_id)
    _require_edit(db, current_user, resource)

    share = (
        db.query(ResourceShare)
        .filter(ResourceShare.id == share_id, ResourceShare.resource_id == resource.id)
        .first()
    )
    if share is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Share not found")

    db.delete(share)
    db.flush()
    return None
```

- [ ] **Step 5: Wire the router into the app**

In `api/app/main.py`, add the import and mount:

```python
from fastapi import FastAPI

from app.routers.auth import router as auth_router
from app.routers.shares import router as shares_router
from app.routers.tracks import router as tracks_router
from app.routers.waypoints import router as waypoints_router

app = FastAPI(title="AlpineQuest SaaS API")
app.include_router(auth_router)
app.include_router(waypoints_router)
app.include_router(tracks_router)
app.include_router(shares_router)


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd api && pytest tests/test_shares_api.py -v`
Expected: all 8 tests PASS.

- [ ] **Step 7: Run the full suite**

Run: `cd api && pytest -v`
Expected: every test in the project PASSES.

- [ ] **Step 8: Commit**

```bash
git add api/app/schemas/shares.py api/app/routers/shares.py api/app/main.py api/tests/test_shares_api.py
git commit -m "feat: add resource sharing endpoints"
```
