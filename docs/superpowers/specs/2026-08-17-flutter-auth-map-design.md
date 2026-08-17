# Flutter Frontend: Auth + Empty Map — Design

Date: 2026-08-17
Status: Approved, pending implementation plan

## Context

`alpinequest-saas` has been backend-only so far: a FastAPI API with auth
(`POST /auth/register`, `POST /auth/login`, `GET /auth/me`) and resource
CRUD/sharing (`/waypoints`, `/tracks`, `/resources/{id}/shares`), all
implemented and tested (106/106 tests passing on `main`). There is no
client. This spec covers the first frontend slice: a Flutter (Android)
app that can register/log in a user and render an empty MapLibre map —
proving the whole stack (auth, token storage, map rendering) works
end-to-end before waypoint/track/sharing UI is layered on in later,
separately-specced slices.

This follows the platform choice recorded in
[[project_original_design_vs_actual]]: the original AlpineQuest design
(project-main, 2026-08-08) specifies Flutter + MapLibre Native for Android
(MVP), not a web frontend — confirmed as the still-current intent.

### Tile source

The original design assumed MapLibre would point at the existing
`mbtileserver` "unchanged." In practice `mbtileserver` in `project-main`
serves **raster** PNG tiles (`flutter_map` + `TileLayer`, confirmed by
reading `map_screen.dart`) transferred to the QNAP deployment target via USB
— there is no vector `.mbtiles` dataset anywhere in either repo, and
generating one (OSM extract → Planetiler/tilemaker) is a separate, later
initiative. For this slice, the map uses a public vector style —
**OpenFreeMap** (`https://tiles.openfreemap.org/styles/liberty`, no API key,
full OSM-derived data: roads/buildings/POIs) — as the tile/style source.
Swapping in a self-hosted vector source later is a style-URL change, not an
architecture change.

## Decisions

### 1. Platform and project layout

Flutter app at `/app`, alongside `/api`. Android is the only build target
for this slice (Desktop is an explicit later phase per the original design).
Package ID: `com.alpinequest.app`.

### 2. State management: Riverpod

`flutter_riverpod` — matches the state-management library already used in
`project-main`'s Flutter app (`pubspec.yaml`: `flutter_riverpod: ^2.6.1`),
so patterns already known to the team carry over.

### 3. Map engine: `maplibre_gl`

The community-maintained Flutter plugin wrapping MapLibre Native
(BSD-2-Clause), per the tile-engine decision already recorded in
[[project_original_design_vs_actual]]. No alternative considered here —
this was decided in the original design; this spec only fixes the concrete
package.

### 4. Navigation: plain `Navigator` with named routes

Three screens (`/login`, `/register`, `/map`) don't justify a routing
package (`go_router` etc.) — `MaterialApp.routes` + `Navigator.pushNamed` is
sufficient and adds no dependency.

### 5. Auth: token storage and session bootstrap

- JWT stored via `flutter_secure_storage` (Android Keystore-backed).
- On app start, `AuthController` (a Riverpod `AsyncNotifier`) checks for a
  stored token; if present, calls `GET /auth/me` to validate it and load the
  current user. Success → land on `MapScreen`. Failure (401, network error)
  → delete the stored token, land on `LoginScreen`.
- No refresh-token flow — the backend issues a single 24h-lived JWT (see
  [auth API design](2026-08-15-auth-api-design.md)); when it expires, the
  `/auth/me` bootstrap check (or any subsequent 401 from an API call) simply
  routes back to `LoginScreen`. Silent refresh is out of scope for this
  slice.
- Logout: clears the stored token and returns to `LoginScreen`. No
  server-side call — the backend has no token-revocation endpoint (JWTs
  aren't tracked server-side), so logout is purely a client-side action.

### 6. API client and base URL

A single `ApiClient` (thin wrapper over `package:http`) holds the base URL
and attaches `Authorization: Bearer <token>` when a token is present. Base
URL is a compile-time `--dart-define=API_BASE_URL=...`, defaulting to
`http://10.0.2.2:8000` (the standard Android-emulator alias for the host
machine's `localhost`, where `docker-compose`'s `api` service listens on
`:8000`). Running against a physical device over Wi-Fi means passing the
host machine's LAN IP via the same `--dart-define` — documented in the
plan, not hardcoded.

### 7. Error handling

- Auth form errors (422 validation, 409 email-taken, 401 wrong
  credentials) are parsed into a short user-facing message and shown
  inline under the form (a `Text` widget in error color), not a dialog —
  keeps the failure visible next to the field the user is about to retry.
- Network-level failures (no connectivity, timeout, unparseable response)
  show a generic "Could not connect" inline message with the same
  placement.
- `MapScreen` has no data-fetching of its own yet (no waypoints/tracks
  layer in this slice) — the only failure mode is the map tile source
  being unreachable, which `maplibre_gl` handles internally (blank/gray
  tiles, no app-level error handling needed).

### 8. Testing approach

- Widget tests: `LoginScreen` and `RegisterScreen` — field validation
  (empty email/password blocked from submitting), loading state disables
  the submit button, error message renders on a mocked failure response.
- Unit tests: `AuthController` state transitions
  (`unauthenticated` → `authenticating` → `authenticated`/error) and
  `ApiClient`/`AuthRepository` request construction, using a mocked HTTP
  client (`package:http`'s `MockClient`) — no real network calls, no
  backend dependency for the test suite.
- `MapScreen`: a minimal smoke test asserting it builds without throwing.
  Full visual/interaction verification (tiles actually render, pan/zoom
  works) is manual, on a physical device or emulator — see Out of scope.
- No integration/end-to-end tests against a running backend in this slice
  (would require docker-compose in CI, deferred).

## Data flow

**App start:** `AuthController` reads token from secure storage → if
present, `GET /auth/me` → valid → `MapScreen`; invalid/absent → `LoginScreen`.

**Register:** form submit → `POST /auth/register` → 200: store token,
`AuthController` → `authenticated`, navigate to `MapScreen`. 409/422/network
error: inline error message, form stays.

**Login:** same shape as register, against `POST /auth/login` (401 instead
of 409 for the "wrong credentials" case).

**Logout:** clear stored token → `AuthController` → `unauthenticated` →
navigate to `LoginScreen`.

**Map:** `MapScreen` mounts → `maplibre_gl` `MapLibreMap` widget with the
OpenFreeMap style URL → renders. No app-level data flow yet.

## Out of scope (for this slice)

- Waypoint/track rendering, creation, or editing on the map.
- Sharing UI.
- Offline tiles / offline regions.
- Silent token refresh.
- iOS, Desktop.
- Automated device/emulator verification in CI — the development machine's
  Android emulator currently fails to boot (reproducible `qemu` crash,
  cause undetermined — see project memory). Live verification is manual, on
  a developer's own device, until that's resolved or a working emulator is
  available.

## Components (file structure)

```
app/
  pubspec.yaml
  lib/
    main.dart                        # MaterialApp, routes, ProviderScope
    config.dart                      # API_BASE_URL from --dart-define
    api/
      api_client.dart                # http wrapper, auth header injection
    auth/
      auth_repository.dart           # register/login/me HTTP calls
      auth_controller.dart           # Riverpod AsyncNotifier, session state
      token_storage.dart             # flutter_secure_storage wrapper
      login_screen.dart
      register_screen.dart
    map/
      map_screen.dart                # MapLibreMap + OpenFreeMap style
  test/
    auth/
      auth_controller_test.dart
      auth_repository_test.dart
      login_screen_test.dart
      register_screen_test.dart
    map/
      map_screen_test.dart
```
