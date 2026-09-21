# Remove client auth, single implicit user — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the login/registration/token flow from the Flutter app; the backend serves every request as one fixed user when `AUTH_DISABLED=true`.

**Architecture:** Backend gains an opt-in single-user mode in `get_current_user` (default off, so token auth, roles, sharing and their tests are untouched). The client drops the `token` parameter from `ApiClient`, repositories and controllers, deletes `lib/auth/`, and opens `HomeShell` directly.

**Tech Stack:** FastAPI + SQLAlchemy + pytest (api/), Flutter + Riverpod + flutter_test (app/), Docker Compose, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-21-remove-auth-single-user-design.md`

## Global Constraints

- `AUTH_DISABLED` defaults to `False`; token-mode behaviour and all existing backend tests must keep passing unchanged.
- Single user email default: `alpinequest.dev@example.com` (reuses the existing dev account so existing waypoints/tracks keep their owner).
- `/auth/*` endpoints stay in the API; the client no longer calls them.
- Settings tab stays as an empty screen (title `Настройки`, no other UI). Do not invent any new UI text or screens.
- Backend tests need the Postgres container from `docker-compose.yml` running (`docker compose up -d db`); run them with `api/.venv/Scripts/python.exe -m pytest`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- Working branch is `main`; do not push until Task 3.

---

### Task 1: Backend single-user mode

**Files:**
- Modify: `api/app/config.py`
- Modify: `api/app/dependencies.py`
- Modify: `docker-compose.yml`
- Create: `api/tests/test_single_user_mode.py`

**Interfaces:**
- Consumes: `create_personal_organization_and_owner(db, *, email, password_hash) -> User` (`app/services/organizations.py`), `hash_password(str) -> str` (`app/services/auth.py`).
- Produces: `settings.AUTH_DISABLED: bool`, `settings.SINGLE_USER_EMAIL: str`; `get_current_user` returns the single user when the flag is on.

- [ ] **Step 1: Write the failing tests**

Create `api/tests/test_single_user_mode.py`:

```python
import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.services.auth import hash_password, verify_password
from app.services.organizations import create_personal_organization_and_owner

SINGLE_EMAIL = "single-user@example.test"


def _make_app(db_session):
    app = FastAPI()

    @app.get("/whoami")
    def whoami(user: User = Depends(get_current_user)):
        return {"id": str(user.id), "email": user.email}

    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    return app


@pytest.fixture()
def single_user_mode(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_DISABLED", True)
    monkeypatch.setattr(settings, "SINGLE_USER_EMAIL", SINGLE_EMAIL)


def test_request_without_header_succeeds_and_creates_the_user(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.status_code == 200
    assert response.json()["email"] == SINGLE_EMAIL
    assert db_session.query(User).filter(User.email == SINGLE_EMAIL).count() == 1


def test_repeated_requests_return_the_same_user(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    first = client.get("/whoami").json()
    second = client.get("/whoami").json()

    assert first["id"] == second["id"]
    assert db_session.query(User).filter(User.email == SINGLE_EMAIL).count() == 1


def test_garbage_token_is_ignored(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami", headers={"Authorization": "Bearer garbage"})

    assert response.status_code == 200
    assert response.json()["email"] == SINGLE_EMAIL


def test_existing_active_user_is_reused(db_session, single_user_mode):
    existing = create_personal_organization_and_owner(
        db_session, email=SINGLE_EMAIL, password_hash=hash_password("whatever")
    )
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.json()["id"] == str(existing.id)


def test_created_user_has_a_valid_but_unguessable_password_hash(db_session, single_user_mode):
    client = TestClient(_make_app(db_session))
    client.get("/whoami")
    user = db_session.query(User).filter(User.email == SINGLE_EMAIL).one()

    # Must be a well-formed bcrypt hash (so POST /auth/login for this email
    # returns 401 instead of crashing), and must not match trivial passwords.
    assert verify_password("", user.password_hash) is False
    assert verify_password("password", user.password_hash) is False


def test_flag_off_still_requires_a_token(db_session):
    client = TestClient(_make_app(db_session))

    response = client.get("/whoami")

    assert response.status_code == 401
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from repo root): `docker compose up -d db && cd api && .venv/Scripts/python.exe -m pytest tests/test_single_user_mode.py -v`
Expected: the five `single_user_mode` tests FAIL with `AttributeError`/`AssertionError` (settings has no `AUTH_DISABLED` yet, so `monkeypatch.setattr` raises); `test_flag_off_still_requires_a_token` PASSES.

- [ ] **Step 3: Add the settings**

In `api/app/config.py`, replace the `Settings` fields block with:

```python
class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql://alpinequest:alpinequest@localhost:5433/alpinequest"
    JWT_SECRET_KEY: str = "dev-secret-change-me"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    # Single-user mode: access is protected outside the app (VPN), so every
    # request is served as SINGLE_USER_EMAIL and no token is required.
    AUTH_DISABLED: bool = False
    SINGLE_USER_EMAIL: str = "alpinequest.dev@example.com"

    class Config:
        env_file = ".env"
```

- [ ] **Step 4: Implement single-user resolution**

Replace the whole of `api/app/dependencies.py` with:

```python
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models.user import User
from app.services.auth import InvalidTokenError, decode_access_token, hash_password
from app.services.organizations import create_personal_organization_and_owner

bearer_scheme = HTTPBearer(auto_error=False)

_CREDENTIALS_ERROR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
)


def _get_or_create_single_user(db: Session) -> User:
    user = (
        db.query(User)
        .filter(User.email == settings.SINGLE_USER_EMAIL, User.deleted_at.is_(None))
        .first()
    )
    if user is None:
        # A well-formed bcrypt hash of a random secret: nobody can log in as
        # this user, and /auth/login stays a clean 401 instead of a crash.
        user = create_personal_organization_and_owner(
            db,
            email=settings.SINGLE_USER_EMAIL,
            password_hash=hash_password(secrets.token_urlsafe(32)),
        )
    return user


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if settings.AUTH_DISABLED:
        return _get_or_create_single_user(db)

    if credentials is None:
        raise _CREDENTIALS_ERROR

    try:
        user_id = decode_access_token(credentials.credentials)
    except InvalidTokenError:
        raise _CREDENTIALS_ERROR

    user = db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
    if user is None:
        raise _CREDENTIALS_ERROR

    return user
```

- [ ] **Step 5: Enable the mode in Docker Compose**

In `docker-compose.yml`, under `api:` → `environment:`, add a line so it reads:

```yaml
    environment:
      DATABASE_URL: postgresql://alpinequest:alpinequest@db:5432/alpinequest
      JWT_SECRET_KEY: dev-secret-change-me
      AUTH_DISABLED: "true"
```

- [ ] **Step 6: Run the full backend suite**

Run: `cd api && .venv/Scripts/python.exe -m pytest -q`
Expected: all tests pass (previously 127, now 133).

- [ ] **Step 7: Verify against the running container**

Run: `docker compose up -d --force-recreate api`, wait ~10 s, then
`curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:8500/waypoints?limit=1"`
Expected: `200` (no Authorization header).

- [ ] **Step 8: Commit**

```bash
git add api/app/config.py api/app/dependencies.py api/tests/test_single_user_mode.py docker-compose.yml
git commit -m "feat(api): add AUTH_DISABLED single-user mode

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Client — remove tokens and the auth flow

This is one commit: the token parameter, the auth screens and the token storage
are interdependent, so no smaller slice compiles.

**Files:**
- Create: `app/lib/api/api_client_provider.dart`
- Modify: `app/lib/api/api_client.dart`
- Modify: `app/lib/waypoints/waypoints_repository.dart`, `app/lib/waypoints/waypoints_controller.dart`
- Modify: `app/lib/tracks/tracks_repository.dart`, `app/lib/tracks/tracks_controller.dart`
- Modify: `app/lib/main.dart`, `app/lib/settings/settings_screen.dart`, `app/lib/map/map_screen.dart`, `app/lib/config.dart`
- Modify: `.github/workflows/flutter-build.yml`
- Modify: `docs/superpowers/specs/2026-09-21-remove-auth-single-user-design.md`
- Delete: `app/lib/auth/` and `app/test/auth/`
- Modify (tests): `app/test/api/api_client_test.dart`, `app/test/app_test.dart`, `app/test/settings/settings_screen_test.dart`, `app/test/home/home_shell_test.dart`, `app/test/map/map_screen_test.dart`, `app/test/waypoints/{fakes,waypoints_controller_test,waypoints_list_screen_test,waypoint_actions_test}.dart`, `app/test/tracks/{fakes,tracks_controller_test,tracks_list_screen_test}.dart`

**Interfaces:**
- Produces: `apiClientProvider` in `package:app/api/api_client_provider.dart`; `WaypointsRepository.list()`, `.create({...})`, `.update(String id, {...})`, `.delete(String id)`; `TracksRepository.list()`, `.create({...})`; `WaypointsController.createWaypoint` without `ownerId`; `circleOptionsForWaypoint(Waypoint waypoint)` (single parameter).

All commands below run from `app/` unless stated otherwise. `PY` means `../api/.venv/Scripts/python.exe`.

- [ ] **Step 1: Record the two spec additions**

Append to the "Client" section of `docs/superpowers/specs/2026-09-21-remove-auth-single-user-design.md`, after the `SettingsScreen` bullet:

```markdown
- Own-vs-shared waypoint styling on the map (`currentUserId` in `map_screen.dart`) is
  removed: with a single user every waypoint is "own", so `circleOptionsForWaypoint`
  takes only the waypoint and always uses the thin white stroke. The optimistic
  waypoint created by `createWaypoint` gets an empty `ownerId`; the server response
  replaces it.
```

- [ ] **Step 2: Move `apiClientProvider` and strip the token from `ApiClient`**

Create `app/lib/api/api_client_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.apiBaseUrl);
});
```

Replace `app/lib/api/api_client.dart` with:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  static const Map<String, String> _headers = {'Content-Type': 'application/json'};

  Future<http.Response> get(String path) {
    return _httpClient.get(Uri.parse('$baseUrl$path'), headers: _headers);
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body}) {
    return _httpClient.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> patch(String path, {Map<String, dynamic>? body}) {
    return _httpClient.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> delete(String path) {
    return _httpClient.delete(Uri.parse('$baseUrl$path'), headers: _headers);
  }
}
```

- [ ] **Step 3: Strip the token from repositories and their fakes (scripted, asserted)**

Run this inline from `app/` (it asserts that no `token` text remains):

```bash
../api/.venv/Scripts/python.exe - <<'EOF'
import pathlib, re

def strip_token(s):
    s = s.replace("list(String token)", "list()")
    s = s.replace("(\n    String token, {\n", "({\n")
    s = s.replace("(\n    String token,\n    String id, {", "(\n    String id, {")
    s = s.replace("delete(String token, String id)", "delete(String id)")
    s = re.sub(r"[ ]*token: token,\n", "", s)
    s = s.replace(", token: token)", ")")
    assert "token" not in s, "leftover 'token'"
    return s

for path in [
    "lib/waypoints/waypoints_repository.dart",
    "lib/tracks/tracks_repository.dart",
    "test/waypoints/fakes.dart",
    "test/tracks/fakes.dart",
]:
    p = pathlib.Path(path)
    p.write_text(strip_token(p.read_text(encoding="utf-8")), encoding="utf-8")
    print("ok", path)
EOF
```

Expected: four `ok` lines and no `AssertionError`.

- [ ] **Step 4: Rewrite the controllers**

Replace `app/lib/waypoints/waypoints_controller.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client_provider.dart';
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

  Future<void> loadWaypoints() async {
    try {
      state = await _repository.list();
    } on WaypointException {
      // Initial-load failures aren't surfaced in this slice; the map just
      // stays at whatever it already had (empty, on first load) until the
      // next successful load.
    }
  }

  Future<Waypoint> createWaypoint({
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
    required String? color,
  }) async {
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    // ownerId is unknown client-side (single implicit user); the server
    // response replaces this optimistic entry.
    final optimistic = Waypoint(
      id: tempId,
      orgId: '',
      ownerId: '',
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      color: color,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created = await _repository.create(name: name, type: type, note: note, color: color, lat: lat, lng: lng);
      state = [for (final w in state) if (w.id == tempId) created else w];
      return created;
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
    required String? color,
  }) async {
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
      color: color,
      canEdit: previous.canEdit,
      createdAt: previous.createdAt,
    );
    state = [for (final w in state) if (w.id == id) optimistic else w];

    try {
      final updated = await _repository.update(id, name: name, type: type, note: note, color: color);
      state = [for (final w in state) if (w.id == id) updated else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id == id) previous else w];
      rethrow;
    }
  }

  Future<void> deleteWaypoint(String id) async {
    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    state = [for (final w in state) if (w.id != id) w];

    try {
      await _repository.delete(id);
    } on WaypointException {
      state = [...state, previous];
      rethrow;
    }
  }
}
```

Replace `app/lib/tracks/tracks_controller.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client_provider.dart';
import 'track_models.dart';
import 'tracks_repository.dart';

final tracksRepositoryProvider = Provider<TracksRepository>((ref) {
  return HttpTracksRepository(ref.watch(apiClientProvider));
});

final tracksControllerProvider = NotifierProvider<TracksController, List<Track>>(TracksController.new);

class TracksController extends Notifier<List<Track>> {
  @override
  List<Track> build() => const [];

  TracksRepository get _repository => ref.read(tracksRepositoryProvider);

  Future<void> loadTracks() async {
    try {
      state = await _repository.list();
    } on TrackException {
      // Same intentional silent-swallow as WaypointsController.loadWaypoints():
      // an initial-load failure isn't surfaced in this slice.
    }
  }

  /// No optimistic insert: unlike a waypoint, a just-recorded track has no
  /// "immediately visible on the map" expectation before the user has even
  /// confirmed the save form, so there's nothing to roll back on failure —
  /// [TrackException] simply propagates to the caller.
  Future<void> saveTrack({
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final created = await _repository.create(
      name: name,
      points: points,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
    state = [...state, created];
  }
}
```

- [ ] **Step 5: Delete the auth module and rewire the app shell**

```bash
git rm -r -q lib/auth test/auth
```

Replace `app/lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: AlpineQuestApp()));
}

class AlpineQuestApp extends StatelessWidget {
  const AlpineQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlpineQuest',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
```

Replace `app/lib/settings/settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: const SizedBox.shrink(),
    );
  }
}
```

In `app/lib/config.dart`, delete the trailing block (the comment and `devAutoLoginEnabled`):

```dart
  // TEMPORARY: skips the login screen by auto-authenticating a dev account so
  // the main app flow can be tested without typing credentials. Off by
  // default (and thus in tests/CI); enable with --dart-define=DEV_AUTO_LOGIN=true.
  static const bool devAutoLoginEnabled = bool.fromEnvironment('DEV_AUTO_LOGIN');
```

(also remove the blank line before it so the class ends after `mapStyleUrl`).

In `.github/workflows/flutter-build.yml`, change the build line to:

```yaml
        run: flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8500
```

- [ ] **Step 6: Remove the current-user concept from `map_screen.dart`**

Apply these exact edits to `app/lib/map/map_screen.dart`:

1. Delete the line `import '../auth/auth_controller.dart';`.
2. Replace the doc comment + function `circleOptionsForWaypoint` (the block starting `/// Pure mapping from a waypoint (plus the current user id` through its closing `}`) with:

```dart
/// Pure mapping from a waypoint to the [CircleOptions] used to render it.
/// Extracted as a top-level function so it can be unit-tested without a
/// real [MapLibreMapController]/platform view.
CircleOptions circleOptionsForWaypoint(Waypoint waypoint) {
  return CircleOptions(
    geometry: LatLng(waypoint.lat, waypoint.lng),
    circleRadius: 8,
    circleColor: waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: '#FFFFFF',
    circleStrokeWidth: 1,
  );
}
```

3. Delete the line `    final currentUserId = _currentUserId();` (in the circle sync method).
4. Replace the comment + key lines:

```dart
      // circleOptionsForWaypoint is a pure function of (waypoint.type,
      // isOwn, waypoint.color) — nothing else it reads ever varies for a
      // given waypoint id — so this key cheaply captures "would the
      // rendered options change".
      final isOwn = waypoint.ownerId == currentUserId;
      final key = '${waypoint.type}|$isOwn|${waypoint.color ?? ''}';
```

with:

```dart
      // circleOptionsForWaypoint is a pure function of (waypoint.type,
      // waypoint.color) — nothing else it reads ever varies for a given
      // waypoint id — so this key cheaply captures "would the rendered
      // options change".
      final key = '${waypoint.type}|${waypoint.color ?? ''}';
```

5. Replace both `circleOptionsForWaypoint(waypoint, currentUserId)` calls with `circleOptionsForWaypoint(waypoint)`.
6. Delete the `_currentUserId()` method:

```dart
  String _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.user.id : '';
  }
```

7. In `_createWaypointAtCrosshair`, delete the line `            ownerId: _currentUserId(),`.

Verify: `grep -n "currentUserId\|_currentUserId\|auth" lib/map/map_screen.dart` prints nothing.

- [ ] **Step 7: Update the tests (scripted, asserted)**

Run from `app/`:

```bash
../api/.venv/Scripts/python.exe - <<'EOF'
import pathlib, re

def edit(path, fn):
    p = pathlib.Path("test") / path
    s = p.read_text(encoding="utf-8")
    new = fn(s)
    assert new != s, f"no change: {path}"
    p.write_text(new, encoding="utf-8")
    print("ok", path)

FAKES_IMPORT = "import '../auth/fakes.dart';\n"
STORAGE_PAIR = re.compile(r"    final storage = FakeTokenStorage\(\);\n    await storage\.write\('tok-1'\);\n")
TOKEN_DECL = re.compile(r"    final tokenStorage = FakeTokenStorage\(\)\.\.write\('tok-1'\);\n")
OVERRIDE = re.compile(r"[ ]*tokenStorageProvider\.overrideWithValue\((?:storage|tokenStorage)\),\n")
CREATE_OWNER = re.compile(r"(createWaypoint\(\n)\s*ownerId: '[^']*',\n")
NO_TOKEN_TEST = re.compile(
    r"\n    test\('leaves state empty when no token is stored', \(\) async \{.*?\n    \}\);\n", re.S)

def simple(s):
    s = s.replace(FAKES_IMPORT, "")
    s = STORAGE_PAIR.sub("", s)
    s = TOKEN_DECL.sub("", s)
    s = OVERRIDE.sub("", s)
    return s

for f in [
    "waypoints/waypoints_list_screen_test.dart",
    "waypoints/waypoint_actions_test.dart",
    "tracks/tracks_list_screen_test.dart",
    "home/home_shell_test.dart",
]:
    edit(f, simple)

def controller_test(s):
    s = s.replace("import 'package:app/auth/token_storage.dart';\n", "")
    s = s.replace(FAKES_IMPORT, "")
    s = s.replace("  TokenStorage? storage,\n", "")
    s = re.sub(r"  final tokenStorage = storage \?\? \(FakeTokenStorage\(\)\.\.write\('tok-1'\)\);\n", "", s)
    s = OVERRIDE.sub("", s)
    s = NO_TOKEN_TEST.sub("", s)
    s = CREATE_OWNER.sub(r"\1", s)
    return s

edit("waypoints/waypoints_controller_test.dart", controller_test)
edit("tracks/tracks_controller_test.dart", controller_test)

def map_test(s):
    s = s.replace("import 'package:app/auth/auth_controller.dart';\nimport 'package:app/auth/auth_models.dart';\n", "")
    s = s.replace(FAKES_IMPORT, "")
    s = s.replace("  required FakeAuthRepository authRepo,\n  required FakeTokenStorage storage,\n", "")
    s = s.replace("    authRepositoryProvider.overrideWithValue(authRepo),\n    tokenStorageProvider.overrideWithValue(storage),\n", "")
    s = STORAGE_PAIR.sub("", s)
    s = re.sub(r"    final (?:authRepo|repo) = FakeAuthRepository\(\n      meResult: const AuthUser\([^\n]*\),\n    \);\n", "", s)
    s = s.replace("    await container.read(authControllerProvider.notifier).bootstrap();\n", "")
    s = s.replace("_baseOverrides(authRepo: authRepo, storage: storage, ", "_baseOverrides(")
    s = s.replace("_baseOverrides(authRepo: authRepo, storage: storage)", "_baseOverrides()")
    s = s.replace("_baseOverrides(authRepo: repo, storage: storage)", "_baseOverrides()")
    s = CREATE_OWNER.sub(r"\1", s)
    s = s.replace("circleOptionsForWaypoint(waypoint, 'u1')", "circleOptionsForWaypoint(waypoint)")
    s = s.replace("test('own waypoints get a thin white stroke'", "test('waypoints get a thin white stroke'")
    shared = (
        "    test('shared waypoints get a thicker black stroke', () {\n"
        "      final waypoint = waypointWith(ownerId: 'someone-else', type: 'generic');\n"
        "\n"
        "      final options = circleOptionsForWaypoint(waypoint);\n"
        "\n"
        "      expect(options.circleStrokeColor, '#000000');\n"
        "      expect(options.circleStrokeWidth, 2);\n"
        "    });\n"
        "\n"
    )
    assert shared in s
    s = s.replace(shared, "")
    return s

edit("map/map_screen_test.dart", map_test)

def api_client_test(s):
    s = s.replace("get sends request to baseUrl + path with no auth header when token is null",
                  "get sends request to baseUrl + path with no Authorization header")
    s = re.sub(r"  test\('get attaches Authorization header when token is provided'.*?\n  \}\);\n\n", "", s, flags=re.S)
    s = s.replace("delete sends DELETE with Authorization header when token is provided",
                  "delete sends DELETE to baseUrl + path with no Authorization header")
    s = s.replace("client.delete('/waypoints/1', token: 'abc123')", "client.delete('/waypoints/1')")
    s = s.replace("    expect(capturedHeaders!['Authorization'], 'Bearer abc123');\n",
                  "    expect(capturedHeaders!.containsKey('Authorization'), isFalse);\n")
    return s

edit("api/api_client_test.dart", api_client_test)
EOF
```

Expected: seven `ok` lines, no `AssertionError`.

Replace `app/test/app_test.dart` with:

```dart
import 'package:app/compass/compass_source.dart';
import 'package:app/main.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compass/fakes.dart';
import 'tracks/fakes.dart';
import 'waypoints/fakes.dart';

void main() {
  testWidgets('opens straight into the app shell with no login step', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        ],
        child: const AlpineQuestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsNothing);
    expect(find.byKey(const Key('nav_settings')), findsOneWidget);
    expect(find.byKey(const Key('nav_map')), findsOneWidget);
  });
}
```

Replace `app/test/settings/settings_screen_test.dart` with:

```dart
import 'package:app/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only the title and has no logout entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.byKey(const Key('settings_logout_button')), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
}
```

- [ ] **Step 8: Check for leftovers**

Run: `grep -rnE "token|Token|auth/|AuthController|AuthState|devAutoLogin|DEV_AUTO_LOGIN" lib test ../.github`
Expected: no output. (If a hit remains in a test, it is a stale reference — remove it the same way as its siblings.)

- [ ] **Step 9: Analyze and run the full client suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`. If `flutter analyze` reports an unused import (e.g. `waypoint_models.dart` in a test), delete that import and rerun.

- [ ] **Step 10: Commit**

```bash
cd ..
git add -A app .github docs/superpowers/specs/2026-09-21-remove-auth-single-user-design.md
git commit -m "feat(app): remove login, registration and token handling

The backend now runs in single-user mode, so the client no longer
authenticates. Opens straight into HomeShell; settings is an empty screen.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Push, CI build, deploy to the phone

**Files:** none (verification and deployment).

**Interfaces:** Consumes: Task 1 backend running with `AUTH_DISABLED=true`; Task 2 client.

- [ ] **Step 1: Confirm both suites are green from a clean state**

Run: `cd api && .venv/Scripts/python.exe -m pytest -q && cd ../app && flutter analyze && flutter test`
Expected: all pass.

- [ ] **Step 2: Push and wait for CI**

Run: `git push origin main`, then `gh run watch` (pick the latest `flutter-build` run).
Expected: run succeeds and uploads the `app-debug-apk` artifact.

- [ ] **Step 3: Ask the user to download the artifact**

The user downloads it to `Downloads` (it extracts as `app-debug-apk (N)/app-debug.apk`). Do not proceed until the user confirms.

- [ ] **Step 4: Install on the phone (ask before uninstalling)**

Per the deploy workflow: try `adb install -r <apk>`. On `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, ask the user to confirm the uninstall (it wipes local-only data such as per-waypoint icon assignments), then `adb uninstall com.alpinequest.app && adb install -r <apk>`. adb is at `C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe`, device `912532310413`.

- [ ] **Step 5: Tunnel and backend check**

Run: `adb reverse tcp:8500 tcp:8500`, `adb reverse --list`, `docker ps` (containers `alpinequest-saas-api-1` and `-db-1` must be up), and `curl -s http://127.0.0.1:8500/health`.

- [ ] **Step 6: Verify on the device**

Launch: `adb shell monkey -p com.alpinequest.app -c android.intent.category.LAUNCHER 1`, then screenshot with `adb shell screencap -p`.
Expected: the map screen opens immediately (no login form); the "Метки" tab lists the previously created waypoints (same owner as before); creating a waypoint still works; the "Настройки" tab is empty apart from its title.
