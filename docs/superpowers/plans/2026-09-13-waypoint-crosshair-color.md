# Waypoint Crosshair Creation + Custom Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace long-press waypoint creation with a persistent crosshair + create button, and let users override a waypoint's color independently of its type.

**Architecture:** A nullable `color` hex string flows end-to-end: `Waypoint` model → Alembic migration → Pydantic schemas (hex-validated) → service/router (with explicit "clear vs. leave unchanged" semantics on update) → Dart model → repository → controller → `WaypointFormSheet` (swatch + `flutter_colorpicker` dialog) → `circleOptionsForWaypoint`. Separately, `MapScreen` drops `onMapLongClick` and gains a `trackCameraPosition`-backed floating action button that reads the map's center coordinate.

**Tech Stack:** FastAPI + SQLAlchemy + Alembic + Pydantic v2 (backend), Flutter + Riverpod + maplibre_gl + flutter_colorpicker (frontend).

**Spec:** `docs/superpowers/specs/2026-09-13-waypoint-crosshair-color-design.md`

## Global Constraints

- Color values are always 7-character hex strings matching `^#[0-9A-Fa-f]{6}$` (e.g. `#43A047`). No alpha channel, no shorthand 3-digit hex.
- `color: null` (or omitted at the Dart model layer) always means "use the type's default color" — never a real color value.
- On `PATCH /waypoints/{id}`, the presence of the `color` key in the request JSON — not its value — decides behavior: key absent → leave unchanged; key present as `null` → clear the override; key present as a hex string → set it. This is implemented via Pydantic v2's `model_fields_set`, not `is not None`.
- No code, assets, or UI design copied from the AlpineQuest APK or its `flutter_ui/` reference folder (existing settled constraint from `docs/superpowers/specs/2026-08-*` design docs).
- Existing waypoints/tracks tests must keep passing; do not change unrelated behavior.
- Verify backend changes with a real `alembic upgrade head` + `pytest` run against a live Postgres/PostGIS container before considering the branch done — do not trust `Base.metadata.create_all`-only test runs as migration verification (see `[[project_migration_test_gap]]`).

---

## Task 1: Backend — `color` column on `Waypoint` + migration

**Files:**
- Modify: `api/app/models/waypoint.py`
- Create: `api/alembic/versions/<new_revision>_add_color_to_waypoints.py`
- Test: `api/tests/test_waypoint_model.py`

**Interfaces:**
- Produces: `Waypoint.color: str | None` (SQLAlchemy mapped column, nullable, `String(7)`), usable by Task 3's `create_waypoint()`.

- [ ] **Step 1: Write the failing test**

Add to `api/tests/test_waypoint_model.py`:

```python
def test_waypoint_color_defaults_to_none(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner-color@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    waypoint = Waypoint(id=resource.id, name="Trailhead", geom=from_shape(Point(7.6, 45.9), srid=4326))
    db_session.add(waypoint)
    db_session.flush()

    assert waypoint.color is None


def test_waypoint_color_can_be_set(db_session):
    org = Organization(name="Acme Corp", plan="free")
    db_session.add(org)
    db_session.flush()

    owner = User(org_id=org.id, email="owner-color2@acme.test", password_hash="hashed")
    db_session.add(owner)
    db_session.flush()

    resource = Resource(org_id=org.id, owner_id=owner.id, resource_type=ResourceType.WAYPOINT)
    db_session.add(resource)
    db_session.flush()

    waypoint = Waypoint(
        id=resource.id, name="Trailhead", geom=from_shape(Point(7.6, 45.9), srid=4326), color="#FF00AA"
    )
    db_session.add(waypoint)
    db_session.flush()

    assert waypoint.color == "#FF00AA"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -T api pytest tests/test_waypoint_model.py -v`
Expected: FAIL — `TypeError: 'color' is an invalid keyword argument for Waypoint` (or `AttributeError` if using positional-style construction; either way, the column doesn't exist yet).

- [ ] **Step 3: Add the column to the model**

In `api/app/models/waypoint.py`, add after the existing `note` column:

```python
    color: Mapped[str | None] = mapped_column(String(7), nullable=True)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -T api pytest tests/test_waypoint_model.py -v`
Expected: PASS (both new tests, plus the existing `test_create_waypoint_shares_id_with_resource`).

- [ ] **Step 5: Generate and check the Alembic migration**

The current head revision is `7d7472006ec0` (add track measurement fields). Run:

```bash
docker compose exec -T api alembic revision -m "add color to waypoints"
```

This creates a new file under `api/alembic/versions/`. Edit it to match this shape (fill in the generated `revision` id, keep `down_revision = '7d7472006ec0'`):

```python
"""add color to waypoints

Revision ID: <generated>
Revises: 7d7472006ec0
Create Date: <generated>

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '<generated>'
down_revision: Union[str, None] = '7d7472006ec0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "waypoints",
        sa.Column("color", sa.String(length=7), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("waypoints", "color")
```

- [ ] **Step 6: Verify the migration against a real database**

```bash
docker compose exec -T api alembic upgrade head
```

Expected: log line `Running upgrade 7d7472006ec0 -> <generated>, add color to waypoints` with no errors.

- [ ] **Step 7: Commit**

```bash
git add api/app/models/waypoint.py api/alembic/versions/*_add_color_to_waypoints.py api/tests/test_waypoint_model.py
git commit -m "feat: add nullable color column to waypoints

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Backend — hex-validated `color` in Pydantic schemas

**Files:**
- Modify: `api/app/schemas/waypoints.py`
- Test: `api/tests/test_waypoints_api.py` (schema validation exercised through the API, matching this codebase's existing test style — there's no separate schema-unit-test file for waypoints)

**Interfaces:**
- Consumes: none new.
- Produces: `WaypointCreateRequest.color: str | None`, `WaypointUpdateRequest.color: str | None`, `WaypointResponse.color: str | None` — all validated by a shared `^#[0-9A-Fa-f]{6}$` pattern. Task 3's router reads `"color" in payload.model_fields_set` on `WaypointUpdateRequest`.

- [ ] **Step 1: Write the failing test**

Add to `api/tests/test_waypoints_api.py`:

```python
def test_create_waypoint_accepts_valid_hex_color(client):
    headers = _register(client, "waypoint-color-valid@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Colorful",
            "type": "generic",
            "color": "#FF00AA",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["color"] == "#FF00AA"


def test_create_waypoint_rejects_malformed_color(client):
    headers = _register(client, "waypoint-color-bad@example.test")
    response = client.post(
        "/waypoints",
        json={
            "name": "Bad Color",
            "type": "generic",
            "color": "red",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    assert response.status_code == 422


def test_create_waypoint_without_color_defaults_to_none(client):
    headers = _register(client, "waypoint-color-none@example.test")
    response = client.post(
        "/waypoints",
        json={"name": "No Color", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["color"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -T api pytest tests/test_waypoints_api.py -k color -v`
Expected: FAIL — `test_create_waypoint_accepts_valid_hex_color` and `test_create_waypoint_without_color_defaults_to_none` fail with `KeyError: 'color'` (response has no such key yet); `test_create_waypoint_rejects_malformed_color` fails because the request currently succeeds (color is ignored, not validated) instead of returning 422.

- [ ] **Step 3: Add the field + validator to the schemas**

In `api/app/schemas/waypoints.py`, add near the top:

```python
import re

from pydantic import field_validator

_HEX_COLOR_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _validate_hex_color(v: str | None) -> str | None:
    if v is not None and not _HEX_COLOR_PATTERN.match(v):
        raise ValueError("color must be a hex string like #RRGGBB")
    return v
```

Update the three request/response models:

```python
class WaypointCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    type: str = Field(min_length=1)
    note: str | None = Field(default=None, max_length=500)
    color: str | None = Field(default=None)
    geom: GeoJSONPoint

    @field_validator("color")
    @classmethod
    def _color_is_hex(cls, v: str | None) -> str | None:
        return _validate_hex_color(v)


class WaypointUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    type: str | None = Field(default=None, min_length=1)
    note: str | None = Field(default=None, max_length=500)
    color: str | None = Field(default=None)
    geom: GeoJSONPoint | None = None

    @field_validator("color")
    @classmethod
    def _color_is_hex(cls, v: str | None) -> str | None:
        return _validate_hex_color(v)


class WaypointResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    owner_id: uuid.UUID
    name: str
    type: str
    note: str | None
    color: str | None
    geom: GeoJSONPoint
    can_edit: bool
    created_at: datetime
```

- [ ] **Step 4: Wire the router to read/return `color`**

This step touches the router minimally just to make Step-3's tests pass; full update-semantics (the `model_fields_set` clear/leave-unchanged behavior) is Task 3. For now, in `api/app/routers/waypoints.py`:

In `_to_response`, add `color=entity.color,` to the returned `WaypointResponse(...)`.

In `create()`, pass `color=payload.color` through to `create_waypoint(...)` (this call will fail until Task 3 adds the parameter — see Task 3 Step 3, which must land together with this step for the test to pass; if executing tasks strictly in order, do Task 3's Step 3 change to `create_waypoint` now too, since Task 2's own test requires it end-to-end).

Concretely, also apply now (pulled forward from Task 3 to keep this task's tests green):

`api/app/services/resources.py`, `create_waypoint` signature becomes:

```python
def create_waypoint(
    db: Session,
    *,
    org_id: uuid.UUID,
    owner_id: uuid.UUID,
    name: str,
    geom,
    type: str,
    note: str | None = None,
    color: str | None = None,
) -> Waypoint:
    resource = Resource(org_id=org_id, owner_id=owner_id, resource_type=ResourceType.WAYPOINT)
    db.add(resource)
    db.flush()
    waypoint = Waypoint(id=resource.id, name=name, geom=geom, type=type, note=note or None, color=color)
    db.add(waypoint)
    db.flush()
    return waypoint
```

And in the router's `create()`:

```python
    entity = create_waypoint(
        db,
        org_id=current_user.org_id,
        owner_id=current_user.id,
        name=payload.name,
        geom=geojson_to_point(payload.geom),
        type=payload.type,
        note=payload.note,
        color=payload.color,
    )
```

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec -T api pytest tests/test_waypoints_api.py -k color -v`
Expected: PASS (all three).

- [ ] **Step 6: Run the full backend test suite to check nothing else broke**

Run: `docker compose exec -T api pytest -q`
Expected: all tests pass (existing `create_waypoint` call sites in `test_resources_service.py` don't pass `color`, which is fine since it defaults to `None`).

- [ ] **Step 7: Commit**

```bash
git add api/app/schemas/waypoints.py api/app/routers/waypoints.py api/app/services/resources.py api/tests/test_waypoints_api.py
git commit -m "feat: validate and return hex color on waypoint create

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Backend — update-endpoint clear/leave-unchanged semantics for `color`

**Files:**
- Modify: `api/app/routers/waypoints.py`
- Test: `api/tests/test_waypoints_api.py`

**Interfaces:**
- Consumes: `WaypointUpdateRequest.color` (Task 2), `Waypoint.color` (Task 1).
- Produces: `PATCH /waypoints/{id}` behavior — omitted `color` key leaves it unchanged, `"color": null` clears it, `"color": "#RRGGBB"` sets it.

- [ ] **Step 1: Write the failing tests**

Add to `api/tests/test_waypoints_api.py`:

```python
def test_update_waypoint_sets_color(client):
    headers = _register(client, "waypoint-update-color-set@example.test")
    create_response = client.post(
        "/waypoints",
        json={"name": "A", "type": "generic", "geom": {"type": "Point", "coordinates": [1.0, 1.0]}},
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"color": "#00FF00"}, headers=headers)
    assert response.status_code == 200
    assert response.json()["color"] == "#00FF00"


def test_update_waypoint_omitting_color_leaves_it_unchanged(client):
    headers = _register(client, "waypoint-update-color-omit@example.test")
    create_response = client.post(
        "/waypoints",
        json={
            "name": "A",
            "type": "generic",
            "color": "#00FF00",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"name": "B"}, headers=headers)
    assert response.status_code == 200
    assert response.json()["color"] == "#00FF00"
    assert response.json()["name"] == "B"


def test_update_waypoint_null_color_clears_it(client):
    headers = _register(client, "waypoint-update-color-clear@example.test")
    create_response = client.post(
        "/waypoints",
        json={
            "name": "A",
            "type": "generic",
            "color": "#00FF00",
            "geom": {"type": "Point", "coordinates": [1.0, 1.0]},
        },
        headers=headers,
    )
    waypoint_id = create_response.json()["id"]

    response = client.patch(f"/waypoints/{waypoint_id}", json={"color": None}, headers=headers)
    assert response.status_code == 200
    assert response.json()["color"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -T api pytest tests/test_waypoints_api.py -k update_waypoint_color -v` (or `-k color` to catch the omit case too)
Expected: `test_update_waypoint_sets_color` and `test_update_waypoint_null_color_clears_it` FAIL because the router never touches `entity.color`; `test_update_waypoint_omitting_color_leaves_it_unchanged` currently passes vacuously (color was never set to begin with in the naive case) but will be a true regression guard once Step 3 lands.

- [ ] **Step 3: Update the router's `update_waypoint`**

In `api/app/routers/waypoints.py`, inside `update_waypoint`, after the existing `if payload.note is not None:` block:

```python
    if "color" in payload.model_fields_set:
        entity.color = payload.color
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -T api pytest tests/test_waypoints_api.py -k color -v`
Expected: PASS (all color-related tests, including the three new ones).

- [ ] **Step 5: Run the full backend suite**

Run: `docker compose exec -T api pytest -q`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add api/app/routers/waypoints.py api/tests/test_waypoints_api.py
git commit -m "feat: support setting/clearing waypoint color independently of other fields

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: Frontend — `Waypoint.color` + `circleOptionsForWaypoint` precedence

**Files:**
- Modify: `app/lib/waypoints/waypoint_models.dart`
- Modify: `app/lib/map/map_screen.dart` (only `circleOptionsForWaypoint` and its circle-cache key in `_syncCircles`)
- Test: `app/test/waypoints/waypoint_models_test.dart`, `app/test/map/map_screen_test.dart`

**Interfaces:**
- Produces: `Waypoint.color: String?`, `circleOptionsForWaypoint(Waypoint, String) -> CircleOptions` now resolves color as `waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!`.

- [ ] **Step 1: Write the failing test for the model**

Add to `app/test/waypoints/waypoint_models_test.dart` (check the file first for its existing `fromJson` test pattern and match it — add a case with `'color': '#FF00AA'` in the JSON asserting `waypoint.color == '#FF00AA'`, and a case with `'color': null` asserting `waypoint.color == null`).

Since the exact existing test helper shape may vary, write it as:

```dart
test('fromJson parses a non-null color', () {
  final json = {
    'id': 'w1',
    'org_id': 'o1',
    'owner_id': 'u1',
    'name': 'Trailhead',
    'type': 'generic',
    'note': null,
    'color': '#FF00AA',
    'geom': {
      'type': 'Point',
      'coordinates': [7.6, 45.9],
    },
    'can_edit': true,
    'created_at': '2026-08-22T10:00:00Z',
  };

  final waypoint = Waypoint.fromJson(json);

  expect(waypoint.color, '#FF00AA');
});

test('fromJson parses a null color', () {
  final json = {
    'id': 'w1',
    'org_id': 'o1',
    'owner_id': 'u1',
    'name': 'Trailhead',
    'type': 'generic',
    'note': null,
    'color': null,
    'geom': {
      'type': 'Point',
      'coordinates': [7.6, 45.9],
    },
    'can_edit': true,
    'created_at': '2026-08-22T10:00:00Z',
  };

  final waypoint = Waypoint.fromJson(json);

  expect(waypoint.color, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoint_models_test.dart`
Expected: FAIL — `The named parameter 'color' isn't defined` / `NoSuchMethodError: Class 'Waypoint' has no instance getter 'color'`.

- [ ] **Step 3: Add the `color` field to `Waypoint`**

In `app/lib/waypoints/waypoint_models.dart`, add `this.color` to the constructor (as an optional named parameter, not `required`), add `final String? color;`, and in `fromJson`, add `color: json['color'] as String?,`. Every existing call site that constructs a `Waypoint` directly (test fixtures) keeps compiling since the parameter is optional and defaults to `null`.

```dart
class Waypoint {
  const Waypoint({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.note,
    this.color,
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
  final String? color;
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
      color: json['color'] as String?,
      lng: (coordinates[0] as num).toDouble(),
      lat: (coordinates[1] as num).toDouble(),
      canEdit: json['can_edit'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/waypoints/waypoint_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing test for color precedence in `circleOptionsForWaypoint`**

Add to the `group('circleOptionsForWaypoint', ...)` block in `app/test/map/map_screen_test.dart`:

```dart
test('a custom color overrides the type color', () {
  final waypoint = Waypoint(
    id: 'w1',
    orgId: 'o1',
    ownerId: 'u1',
    name: 'Summit',
    type: 'danger',
    note: null,
    color: '#123456',
    lat: 1.0,
    lng: 2.0,
    canEdit: true,
    createdAt: DateTime.utc(2026, 8, 22),
  );

  final options = circleOptionsForWaypoint(waypoint, 'u1');

  expect(options.circleColor, '#123456');
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/map/map_screen_test.dart`
Expected: FAIL — `circleOptionsForWaypoint` currently always uses `waypointTypeColors[waypoint.type]`, so `options.circleColor` is `waypointTypeColors['danger']` (`'#E53935'`), not `'#123456'`.

- [ ] **Step 7: Update `circleOptionsForWaypoint` and the circle cache key**

In `app/lib/map/map_screen.dart`:

```dart
CircleOptions circleOptionsForWaypoint(Waypoint waypoint, String currentUserId) {
  final isOwn = waypoint.ownerId == currentUserId;
  return CircleOptions(
    geometry: LatLng(waypoint.lat, waypoint.lng),
    circleRadius: 8,
    circleColor: waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: isOwn ? '#FFFFFF' : '#000000',
    circleStrokeWidth: isOwn ? 1 : 2,
  );
}
```

In `_syncCircles`, the cache key line changes from:

```dart
      final key = '${waypoint.type}|$isOwn';
```

to:

```dart
      final key = '${waypoint.type}|$isOwn|${waypoint.color ?? ''}';
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/map/map_screen_test.dart`
Expected: PASS (including the pre-existing `circleOptionsForWaypoint` tests, which are unaffected since they don't set `color`).

- [ ] **Step 9: Commit**

```bash
git add app/lib/waypoints/waypoint_models.dart app/lib/map/map_screen.dart app/test/waypoints/waypoint_models_test.dart app/test/map/map_screen_test.dart
git commit -m "feat: parse waypoint color and let it override the type color when rendering

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Frontend — thread `color` through `WaypointsRepository`

**Files:**
- Modify: `app/lib/waypoints/waypoints_repository.dart`
- Modify: `app/test/waypoints/fakes.dart`
- Test: `app/test/waypoints/waypoints_repository_test.dart`

**Interfaces:**
- Consumes: `Waypoint.color` (Task 4).
- Produces: `WaypointsRepository.create({..., String? color})`, `WaypointsRepository.update({..., String? color})` — both send `'color'` as a JSON key with the given value (`null` included explicitly), matching the backend's clear/set/omit contract from Task 3 (this app always sends the key; it never omits it, which is a valid subset of that contract — see plan Task 3's note that omission is a *leave-unchanged* signal this client doesn't need to use).

- [ ] **Step 1: Write the failing tests**

In `app/test/waypoints/waypoints_repository_test.dart`, update the `create` group's success test to also assert `color` in the captured body, and add a new test:

```dart
test('sends a null color when none is provided', () async {
  Map<String, dynamic>? capturedBody;
  final client = ApiClient(
    baseUrl: 'http://example.test',
    httpClient: MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_waypointJson), 201);
    }),
  );
  final repo = HttpWaypointsRepository(client);

  await repo.create('tok-1', name: 'Trailhead', type: 'generic', note: '', color: null, lat: 45.9, lng: 7.6);

  expect(capturedBody!['color'], isNull);
  expect(capturedBody!.containsKey('color'), isTrue);
});

test('sends a hex color when provided', () async {
  Map<String, dynamic>? capturedBody;
  final client = ApiClient(
    baseUrl: 'http://example.test',
    httpClient: MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_waypointJson), 201);
    }),
  );
  final repo = HttpWaypointsRepository(client);

  await repo.create(
    'tok-1',
    name: 'Trailhead',
    type: 'generic',
    note: '',
    color: '#FF00AA',
    lat: 45.9,
    lng: 7.6,
  );

  expect(capturedBody!['color'], '#FF00AA');
});
```

Do the same for `update` (add a `color` parameter to the existing call in the `update` group's success test and assert it round-trips):

```dart
test('sends color along with name/type/note', () async {
  Map<String, dynamic>? capturedBody;
  final client = ApiClient(
    baseUrl: 'http://example.test',
    httpClient: MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_waypointJson), 200);
    }),
  );
  final repo = HttpWaypointsRepository(client);

  await repo.update('tok-1', 'w1', name: 'New name', type: 'danger', note: 'Careful', color: '#00FF00');

  expect(capturedBody!['color'], '#00FF00');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoints_repository_test.dart`
Expected: FAIL — compile error, `color` isn't a defined named parameter on `create`/`update`.

- [ ] **Step 3: Add `color` to the repository interface and implementation**

In `app/lib/waypoints/waypoints_repository.dart`:

```dart
abstract class WaypointsRepository {
  Future<List<Waypoint>> list(String token);

  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  });

  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  });

  Future<void> delete(String token, String id);
}
```

And in `HttpWaypointsRepository`:

```dart
  @override
  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required String? color,
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
        'color': color,
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
    required String? color,
  }) async {
    final response = await _client.patch(
      '/waypoints/$id',
      token: token,
      body: {'name': name, 'type': type, 'note': note, 'color': color},
    );
    if (response.statusCode != 200) {
      throw const WaypointException('Could not update waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
```

Update `app/test/waypoints/fakes.dart`'s `FakeWaypointsRepository` to match the new signatures (add `required String? color` to both `create` and `update` — the fake doesn't need to use the parameter, just accept it).

Also fix the two pre-existing tests in `waypoints_repository_test.dart` that call `create`/`update` without a `color` argument (the "sends name/type/note/geom..." and "throws WaypointException on non-201/200/403" tests, and the `update` equivalents) — add `color: null` (or a value) to each call so they still compile, and update their `capturedBody` expectations to include `'color': null`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/waypoints/waypoints_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoints_repository.dart app/test/waypoints/fakes.dart app/test/waypoints/waypoints_repository_test.dart
git commit -m "feat: thread waypoint color through the repository layer

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: Frontend — thread `color` through `WaypointsController`

**Files:**
- Modify: `app/lib/waypoints/waypoints_controller.dart`
- Test: `app/test/waypoints/waypoints_controller_test.dart`

**Interfaces:**
- Consumes: `WaypointsRepository.create`/`update` with `color` (Task 5).
- Produces: `WaypointsController.createWaypoint({..., String? color})`, `WaypointsController.updateWaypoint(id, {..., String? color})`.

- [ ] **Step 1: Write the failing test**

Check `app/test/waypoints/waypoints_controller_test.dart` for its existing `createWaypoint`/`updateWaypoint` test pattern, then add (adapting to match the file's existing fixture helpers):

```dart
test('createWaypoint passes color through to the repository and optimistic state', () async {
  final storage = FakeTokenStorage();
  await storage.write('tok-1');
  final repo = FakeWaypointsRepository()
    ..createResult = Waypoint(
      id: 'w1',
      orgId: 'o1',
      ownerId: 'u1',
      name: 'Summit',
      type: 'generic',
      note: null,
      color: '#FF00AA',
      lat: 1.0,
      lng: 2.0,
      canEdit: true,
      createdAt: DateTime.utc(2026, 8, 22),
    );
  final container = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      waypointsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  await container.read(waypointsControllerProvider.notifier).createWaypoint(
        ownerId: 'u1',
        name: 'Summit',
        type: 'generic',
        note: '',
        color: '#FF00AA',
        lat: 1.0,
        lng: 2.0,
      );

  expect(container.read(waypointsControllerProvider).single.color, '#FF00AA');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoints_controller_test.dart`
Expected: FAIL — `createWaypoint` has no `color` parameter (compile error).

- [ ] **Step 3: Add `color` to `WaypointsController`**

In `app/lib/waypoints/waypoints_controller.dart`:

```dart
  Future<void> createWaypoint({
    required String ownerId,
    required String name,
    required String type,
    required String note,
    String? color,
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
      color: color,
      lat: lat,
      lng: lng,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created =
          await _repository.create(token, name: name, type: type, note: note, color: color, lat: lat, lng: lng);
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
    String? color,
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
      color: color,
      lat: previous.lat,
      lng: previous.lng,
      canEdit: previous.canEdit,
      createdAt: previous.createdAt,
    );
    state = [for (final w in state) if (w.id == id) optimistic else w];

    try {
      final updated = await _repository.update(token, id, name: name, type: type, note: note, color: color);
      state = [for (final w in state) if (w.id == id) updated else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id == id) previous else w];
      rethrow;
    }
  }
```

Note `color` is optional (not `required`) at the controller level, defaulting to `null`, since most call sites (e.g. any future non-color-aware caller) shouldn't be forced to pass it — unlike the repository layer in Task 5, which always sends the key to the API.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/waypoints/waypoints_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full frontend test suite to check for fallout**

Run: `flutter test`
Expected: all tests pass (any other test constructing a `Waypoint` or calling `createWaypoint`/`updateWaypoint` without `color` still compiles, since it's optional everywhere in this task).

- [ ] **Step 6: Commit**

```bash
git add app/lib/waypoints/waypoints_controller.dart app/test/waypoints/waypoints_controller_test.dart
git commit -m "feat: thread waypoint color through the controller layer

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: Frontend — add `flutter_colorpicker` + hex/Color conversion helpers

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/waypoints/waypoint_color.dart`
- Test: `app/test/waypoints/waypoint_color_test.dart`

**Interfaces:**
- Produces: `Color colorFromHex(String hex)`, `String colorToHex(Color color)` — used by Task 8's color picker dialog.

- [ ] **Step 1: Add the dependency**

In `app/pubspec.yaml`, under `dependencies:`, after `geolocator: ^14.0.2`:

```yaml
  flutter_colorpicker: ^1.1.0
```

Run: `flutter pub get` (from `app/`)
Expected: resolves cleanly, `pubspec.lock` updated.

- [ ] **Step 2: Write the failing test**

Create `app/test/waypoints/waypoint_color_test.dart`:

```dart
import 'package:app/waypoints/waypoint_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colorFromHex parses a 6-digit hex string with full opacity', () {
    final color = colorFromHex('#43A047');

    expect(color.r, closeTo(0x43 / 255, 0.001));
    expect(color.g, closeTo(0xA0 / 255, 0.001));
    expect(color.b, closeTo(0x47 / 255, 0.001));
    expect(color.a, 1.0);
  });

  test('colorToHex formats a Color back to a 6-digit hex string', () {
    const color = Color(0xFF43A047);

    expect(colorToHex(color), '#43A047');
  });

  test('colorFromHex and colorToHex round-trip', () {
    expect(colorToHex(colorFromHex('#1976D2')), '#1976D2');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoint_color_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:app/waypoints/waypoint_color.dart'`.

- [ ] **Step 4: Implement the helpers**

Create `app/lib/waypoints/waypoint_color.dart`:

```dart
import 'package:flutter/material.dart';

/// Parses a `#RRGGBB` hex string (as used throughout the waypoints API and
/// [waypointTypeColors]) into an opaque [Color].
Color colorFromHex(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}

/// Formats an opaque [Color] back into a `#RRGGBB` hex string, discarding
/// alpha (waypoint colors are always fully opaque).
String colorToHex(Color color) {
  String twoDigits(int channel) => channel.toRadixString(16).padLeft(2, '0').toUpperCase();
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${twoDigits(r)}${twoDigits(g)}${twoDigits(b)}';
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/waypoints/waypoint_color_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/waypoints/waypoint_color.dart app/test/waypoints/waypoint_color_test.dart
git commit -m "feat: add flutter_colorpicker dependency and hex/Color helpers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: Frontend — color swatch + picker dialog in `WaypointFormSheet`

**Files:**
- Modify: `app/lib/waypoints/waypoint_form_sheet.dart`
- Test: `app/test/waypoints/waypoint_form_sheet_test.dart`

**Interfaces:**
- Consumes: `colorFromHex`/`colorToHex` (Task 7), `waypointTypeColors` (existing).
- Produces: `WaypointFormResult.color: String?`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/waypoints/waypoint_form_sheet_test.dart` (the existing `_existingWaypoint()` helper needs a `color` field added — leave it `null` unless a specific test needs otherwise):

```dart
testWidgets('swatch defaults to the selected type color when no override is set', (tester) async {
  await tester.pumpWidget(_harness(() {}, (_) {}));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  final swatch = tester.widget<Container>(find.byKey(const Key('waypoint_color_swatch')));
  final decoration = swatch.decoration as BoxDecoration;
  expect(decoration.color, colorFromHex(waypointTypeColors[defaultWaypointType]!));
});

testWidgets('picking a color in the dialog carries it into the form result', (tester) async {
  WaypointFormResult? result;
  await tester.pumpWidget(_harness(() {}, (r) => result = r));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
  await tester.pump();

  await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('waypoint_save_button')));
  await tester.pumpAndSettle();

  // Tapping "Select" without changing the picker's initial selection keeps
  // it at the effective default it was seeded with -- this asserts the
  // round trip works, not a specific chosen hue (see Task 8 Step 3 note on
  // why the exact seeded value is `waypointTypeColors[defaultWaypointType]`
  // for a new waypoint).
  expect(result!.color, waypointTypeColors[defaultWaypointType]);
});

testWidgets('reset to default clears a previously-picked color', (tester) async {
  WaypointFormResult? result;
  await tester.pumpWidget(_harness(() {}, (r) => result = r, existing: _existingWaypoint()));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
  await tester.pumpAndSettle();

  // Now open again and reset.
  await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('waypoint_color_picker_reset_button')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('waypoint_save_button')));
  await tester.pumpAndSettle();

  expect(result!.color, isNull);
});

testWidgets('changing type does not clear a previously-picked custom color', (tester) async {
  WaypointFormResult? result;
  await tester.pumpWidget(_harness(() {}, (r) => result = r));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
  await tester.pump();

  await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('waypoint_type_chip_water')));
  await tester.pump();

  await tester.tap(find.byKey(const Key('waypoint_save_button')));
  await tester.pumpAndSettle();

  expect(result!.type, 'water');
  expect(result!.color, waypointTypeColors[defaultWaypointType]);
});
```

Also update `_existingWaypoint()` to include `color: null,` (or leave it unset since it will become optional, matching Task 4's model change).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/waypoints/waypoint_form_sheet_test.dart`
Expected: FAIL — `waypoint_color_swatch` key not found, `WaypointFormResult` has no `color` getter.

- [ ] **Step 3: Implement the swatch and picker dialog**

Rewrite `app/lib/waypoints/waypoint_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'waypoint_color.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';

class WaypointFormResult {
  const WaypointFormResult({required this.name, required this.type, required this.note, required this.color});

  final String name;
  final String type;
  final String note;
  final String? color;
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
  String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.existing?.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _effectiveColorHex => _selectedColor ?? waypointTypeColors[_selectedType]!;

  Future<void> _openColorPicker() async {
    Color picked = colorFromHex(_effectiveColorHex);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (color) => picked = color,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('waypoint_color_picker_reset_button'),
            onPressed: () => Navigator.of(dialogContext).pop('reset'),
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('waypoint_color_picker_select_button'),
            onPressed: () => Navigator.of(dialogContext).pop('select'),
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );

    if (action == 'select') {
      setState(() => _selectedColor = colorToHex(picked));
    } else if (action == 'reset') {
      setState(() => _selectedColor = null);
    }
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
          Text(isEditing ? 'Редактировать метку' : 'Новая метка', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final type in waypointTypes)
                ChoiceChip(
                  key: Key('waypoint_type_chip_$type'),
                  label: Text(waypointTypeLabels[type] ?? type),
                  selected: _selectedType == type,
                  onSelected: (_) => setState(() => _selectedType = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Цвет'),
              const SizedBox(width: 12),
              GestureDetector(
                key: const Key('waypoint_color_swatch'),
                onTap: _openColorPicker,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorFromHex(_effectiveColorHex),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_note_field'),
            controller: _noteController,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Заметка (необязательно)'),
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
                        color: _selectedColor,
                      ),
                    ),
            child: Text(isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/waypoints/waypoint_form_sheet_test.dart`
Expected: PASS. Also re-check the pre-existing test `save is disabled until a name is entered, then submits name/type/note` — it constructs a `WaypointFormResult` in its "returns null when dismissed" test (`const WaypointFormResult(name: 'sentinel', type: 'generic', note: '')`), which now needs `color: null` added since `color` is a required (non-optional, non-nullable-default) named parameter on the const constructor — update that call site.

- [ ] **Step 5: Commit**

```bash
git add app/lib/waypoints/waypoint_form_sheet.dart app/test/waypoints/waypoint_form_sheet_test.dart
git commit -m "feat: add color swatch and HSV picker to the waypoint form

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 9: Frontend — replace long-press with crosshair + create button in `MapScreen`

**Files:**
- Modify: `app/lib/map/map_screen.dart`
- Test: `app/test/map/map_screen_test.dart`

**Interfaces:**
- Consumes: `WaypointsController.createWaypoint` (Task 6), `WaypointFormResult.color` (Task 8).
- Produces: `MapScreen` with no `onMapLongClick` waypoint creation, a `create_waypoint_button` FAB, and a `map_crosshair` overlay icon.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/map/map_screen_test.dart`:

```dart
testWidgets('shows a persistent crosshair and a create-waypoint button, with no long-press wiring', (tester) async {
  final storage = FakeTokenStorage();
  await storage.write('tok-1');
  final authRepo = FakeAuthRepository(
    meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
  );
  final container = ProviderContainer(
    overrides: _baseOverrides(authRepo: authRepo, storage: storage),
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

  expect(find.byKey(const Key('map_crosshair')), findsOneWidget);
  expect(find.byKey(const Key('create_waypoint_button')), findsOneWidget);

  final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
  expect(map.onMapLongClick, isNull);
});

testWidgets('tapping create-waypoint button before the map controller is ready shows a message, no crash', (tester) async {
  final storage = FakeTokenStorage();
  await storage.write('tok-1');
  final authRepo = FakeAuthRepository(
    meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
  );
  final container = ProviderContainer(
    overrides: _baseOverrides(authRepo: authRepo, storage: storage),
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

  // MapLibreMap has no real platform view under flutter test, so
  // onMapCreated never fires and _controller stays null -- this exercises
  // the FAB's fallback path (real crosshair-driven creation is covered by
  // manual device verification, same precedent as the old long-press flow
  // it replaces).
  await tester.tap(find.byKey(const Key('create_waypoint_button')));
  await tester.pumpAndSettle();

  expect(find.text('Карта ещё не готова'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/map/map_screen_test.dart`
Expected: FAIL — `map_crosshair`/`create_waypoint_button` keys not found; `onMapLongClick` is currently non-null.

- [ ] **Step 3: Implement the crosshair, FAB, and remove long-press wiring**

In `app/lib/map/map_screen.dart`:

Remove the `_onMapLongClick` method entirely (its body's logic moves into a new `_createWaypointAtCrosshair` below), and remove `onMapLongClick: _onMapLongClick,` from the `MapLibreMap(...)` widget. Add `trackCameraPosition: true,` to the same widget.

Add this new method (replacing `_onMapLongClick`):

```dart
  Future<void> _createWaypointAtCrosshair() async {
    final controller = _controller;
    final cameraPosition = controller?.cameraPosition;
    if (controller == null || cameraPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Карта ещё не готова')),
      );
      return;
    }
    final coordinates = cameraPosition.target;
    final result = await showWaypointFormSheet(context);
    if (result == null || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: _currentUserId(),
            name: result.name,
            type: result.type,
            note: result.note,
            color: result.color,
            lat: coordinates.latitude,
            lng: coordinates.longitude,
          );
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
```

Change the `build` method's `Scaffold.body` from a bare `MapLibreMap` to a `Stack`, and add a `floatingActionButton`:

```dart
      body: Stack(
        children: [
          MapLibreMap(
            styleString: AppConfig.mapStyleUrl,
            initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 1),
            trackCameraPosition: true,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
          ),
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.add, key: Key('map_crosshair'), size: 32, color: Colors.black87),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('create_waypoint_button'),
        onPressed: _createWaypointAtCrosshair,
        child: const Icon(Icons.add_location_alt),
      ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/map/map_screen_test.dart`
Expected: PASS, including the updated "creating a waypoint via the controller updates the rendered state" test from before this task (unaffected, it drives the controller directly) and both new tests.

- [ ] **Step 5: Run the full frontend suite and analyzer**

Run: `flutter test`
Expected: all tests pass.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/map/map_screen.dart app/test/map/map_screen_test.dart
git commit -m "feat: replace long-press waypoint creation with crosshair + create button

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 10: Final verification

**Files:** none (verification-only task)

- [ ] **Step 1: Run the full backend suite against a real database**

```bash
docker compose exec -T api alembic upgrade head
docker compose exec -T api pytest -q
```

Expected: migration applies cleanly (log line for the Task 1 migration), all tests pass.

- [ ] **Step 2: Run the full frontend suite and analyzer**

```bash
cd app
flutter test
flutter analyze
```

Expected: all tests pass, 0 analyzer issues.

- [ ] **Step 3: Manual on-device/emulator verification**

Launch the app against the running API and confirm:
- The crosshair sits at the map's visual center regardless of pan/zoom.
- The create-waypoint button opens the form at the crosshair's current coordinate (compare against a known landmark on the map).
- Long-press on the map no longer opens the waypoint form.
- The color swatch defaults to the type's color, opens the HSV picker, and "Сбросить" reverts to the type default.
- Changing a waypoint's type after picking a custom color keeps the custom color.
- A waypoint saved with a custom color renders in that color as a map circle; one saved without a custom color still renders in its type's color.

- [ ] **Step 4: Commit any fixes found during manual verification**

If manual verification surfaces a bug, fix it with its own test-first cycle (write failing test, fix, verify, commit) rather than committing an unverified fix.
