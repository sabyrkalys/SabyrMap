# Track Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user record their GPS path on the map (start/stop), save it as a named `Track`, and toggle visibility of previously saved tracks — all rendered as colored polylines.

**Architecture:** Pure frontend — the existing `/tracks` resource CRUD API already supports everything this slice needs (`LineString` geometry, ≥2-point validation). A new `geolocator`-backed `LocationSource` feeds a local-only `TrackRecordingController` (Riverpod) that accumulates points while recording; on Stop, the points are handed to a server-backed `TracksController` (mirroring `WaypointsController`'s shape) which uploads them once via `POST /tracks`. `MapScreen` renders the in-progress recording and any visible saved tracks as `maplibre_gl` `Line` annotations, reusing and generalizing the circle-sync serialization scheme already built for waypoints.

**Tech Stack:** Flutter + Riverpod + `maplibre_gl` 0.26.2 + `geolocator` (new) + `http`.

**Spec:** `docs/superpowers/specs/2026-08-22-track-recording-slice-design.md`

## Global Constraints

- Recording only runs while `MapScreen` is the active screen — no background/foreground-service recording in this slice.
- No local on-device durability during recording — points live only in `TrackRecordingController`'s in-memory state; an app kill loses an in-progress recording.
- The whole track uploads once, as a single `POST /tracks`, when the user confirms the save form after Stop — no incremental/periodic upload.
- Points captured as `lat`/`lng` only — no elevation or per-point timestamp (deferred to a future stats slice).
- Points are captured by distance, not time (~10 meters between points), via `geolocator`'s `distanceFilter`.
- The backend's `GeoJSONLineString` schema requires **at least 2 coordinates** — the client must not attempt to save a recording with fewer than 2 points.
- Saved tracks are hidden by default; a "Показывать треки" toggle (off by default) in a new layers bottom sheet controls their visibility.
- No track detail/edit/delete UI in this slice — tracks are view-only once saved (create + list only).
- Backend requires no changes for this slice.

---

## File Structure

New files:
- `app/lib/tracks/location_source.dart` — `LocationSource` abstraction + `GeolocatorLocationSource`, decoupled from `TrackPoint`/GPS specifics so it's the only file that imports `geolocator`.
- `app/lib/tracks/track_models.dart` — `TrackPoint`, `Track`, `TrackException`.
- `app/lib/tracks/tracks_repository.dart` — `TracksRepository` (abstract) + `HttpTracksRepository`.
- `app/lib/tracks/tracks_controller.dart` — `TracksController` (server-backed list) + providers.
- `app/lib/tracks/track_recording_controller.dart` — `TrackRecordingController` (local-only recording state machine) + providers.
- `app/lib/tracks/track_name_form_sheet.dart` — the post-Stop "name and save" bottom sheet.

Modified files:
- `app/pubspec.yaml` — add `geolocator`.
- `app/android/app/src/main/AndroidManifest.xml` — add location permissions.
- `app/lib/map/map_screen.dart` — add record/layers AppBar actions, unify the existing circle-sync gate with a new line-sync for saved + in-progress tracks.
- `app/test/map/map_screen_test.dart` — cover the new AppBar actions and overrides for the new providers.

---

## Task 1: Add `geolocator` dependency and Android location permissions

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: the `geolocator` package available for import — consumed by Task 2's `GeolocatorLocationSource`.

- [ ] **Step 1: Add the dependency**

Run, from `app/`: `C:\FlutterSDK\flutter\bin\flutter.bat pub add geolocator`

This fetches the latest compatible version and adds it to `pubspec.yaml` automatically (don't hand-edit the version constraint — let `pub add` resolve it).

- [ ] **Step 2: Add Android location permissions**

In `app/android/app/src/main/AndroidManifest.xml`, add after the existing `<uses-permission android:name="android.permission.INTERNET" />` line:

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Do **not** add `ACCESS_BACKGROUND_LOCATION` — background recording is explicitly out of scope for this slice.

- [ ] **Step 3: Verify the app still builds**

Run, from `app/`: `C:\FlutterSDK\flutter\bin\flutter.bat pub get` then `C:\FlutterSDK\flutter\bin\flutter.bat analyze`
Expected: `pub get` succeeds, `analyze` reports no issues (the new dependency is unused so far, which is fine — it will be consumed starting in Task 2).

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml
git commit -m "build: add geolocator dependency and location permissions"
```

---

## Task 2: `LocationSource` abstraction

**Files:**
- Create: `app/lib/tracks/location_source.dart`
- Test: `app/test/tracks/location_source_test.dart`

**Interfaces:**
- Produces: `abstract class LocationSource` with `Future<bool> ensurePermission()` and `Stream<TrackPoint> positionStream({required int distanceFilterMeters})`; `class GeolocatorLocationSource implements LocationSource`. Consumed by Task 6's `TrackRecordingController` — tests use a fake implementation instead of `GeolocatorLocationSource`, so `TrackRecordingController` never has to construct a real `geolocator` `Position` object.
- Consumes: `TrackPoint` from Task 3 — **do this task after Task 3**, or inline a minimal local `TrackPoint`-shaped return type here and let Task 3 be the canonical definition (the two must end up with identical field names/types: `lat`, `lng`, both `double`). To avoid ambiguity, this plan sequences Task 3 (`track_models.dart`) before this task's implementation step — the brief below assumes `track_models.dart` already exists.

- [ ] **Step 1: Write the failing test**

Create `app/test/tracks/location_source_test.dart`:

```dart
import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TrackPoint carries lat/lng as doubles', () {
    const point = TrackPoint(lat: 45.9, lng: 7.6);
    expect(point.lat, 45.9);
    expect(point.lng, 7.6);
  });
}
```

This is a placeholder test to establish the file before `LocationSource` has a fake to test against — `GeolocatorLocationSource` itself is a thin wrapper around `geolocator`'s static API and is only exercised via manual device verification (there is no way to unit-test real GPS/permission-dialog behavior under `flutter test`). The abstraction's value is that `TrackRecordingController` (Task 6) can be fully unit-tested against a fake `LocationSource` — that's where the real test coverage for this abstraction's *contract* lives.

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/location_source_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/track_models.dart` doesn't exist yet (Task 3 hasn't run). If Task 3 has already been completed when you pick up this task, this step instead fails because `location_source.dart` doesn't exist — either way, confirm the failure is an import/file error, not a logic error.

- [ ] **Step 3: Implement**

Create `app/lib/tracks/location_source.dart`:

```dart
import 'package:geolocator/geolocator.dart';

import 'track_models.dart';

abstract class LocationSource {
  /// Requests location permission if not already granted, and confirms the
  /// device's location service is enabled. Returns false if recording
  /// cannot proceed for any reason (permission denied, denied forever, or
  /// location services disabled).
  Future<bool> ensurePermission();

  /// A stream of positions, filtered so a new event only fires once the
  /// device has moved at least [distanceFilterMeters] from the last
  /// reported position.
  Stream<TrackPoint> positionStream({required int distanceFilterMeters});
}

class GeolocatorLocationSource implements LocationSource {
  @override
  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Stream<TrackPoint> positionStream({required int distanceFilterMeters}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(distanceFilter: distanceFilterMeters),
    ).map((position) => TrackPoint(lat: position.latitude, lng: position.longitude));
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/location_source_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Run static analysis**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat analyze` (from `app/`)
Expected: no issues (confirms the `geolocator` API calls above match the version `pub add` resolved in Task 1 — if analyze reports an unknown member on `Geolocator`/`LocationSettings`/`LocationPermission`, the installed version's API differs from what's written above; check `app/.dart_tool/package_config.json` or run `flutter pub deps` to find the resolved `geolocator` version, then adjust the calls in this file to match that version's actual API — `checkPermission`/`requestPermission`/`isLocationServiceEnabled`/`getPositionStream`/`LocationSettings(distanceFilter:)` have been stable across geolocator's major versions for years, so a mismatch is unlikely but must be checked, not assumed).

- [ ] **Step 6: Commit**

```bash
git add app/lib/tracks/location_source.dart app/test/tracks/location_source_test.dart
git commit -m "feat: add LocationSource abstraction over geolocator"
```

---

## Task 3: `Track`/`TrackPoint`/`TrackException` model

**Files:**
- Create: `app/lib/tracks/track_models.dart`
- Test: `app/test/tracks/track_models_test.dart`

**Interfaces:**
- Produces: `TrackPoint({required lat, required lng})` (plain data class, no `maplibre_gl` dependency — mirrors how `Waypoint` stores `lat`/`lng` as plain doubles rather than a `LatLng`, keeping the data layer decoupled from the map-rendering library); `Track` (`id, orgId, ownerId, name, points, createdAt`, plus `Track.fromJson`); `TrackException` (mirrors `WaypointException`'s shape). Consumed by Tasks 2, 4, 5, 6, 7, 8.

**Note on task order:** this task must be completed before Task 2's Step 3 (`location_source.dart` imports `track_models.dart`). If executing sequentially task-by-task as numbered, this is already satisfied — Task 2 is listed first only because `LocationSource` is the more foundational abstraction conceptually; if dispatching out of order, do Task 3 first.

- [ ] **Step 1: Write the failing test**

Create `app/test/tracks/track_models_test.dart`:

```dart
import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Track.fromJson', () {
    test('parses geom coordinates as [lng, lat] pairs into TrackPoint(lat, lng)', () {
      final json = {
        'id': 't1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Morning walk',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9],
            [7.7, 46.0],
          ],
        },
        'created_at': '2026-08-22T10:00:00Z',
      };

      final track = Track.fromJson(json);

      expect(track.id, 't1');
      expect(track.orgId, 'o1');
      expect(track.ownerId, 'u1');
      expect(track.name, 'Morning walk');
      expect(track.points, hasLength(2));
      expect(track.points[0].lng, 7.6);
      expect(track.points[0].lat, 45.9);
      expect(track.points[1].lng, 7.7);
      expect(track.points[1].lat, 46.0);
      expect(track.createdAt, DateTime.parse('2026-08-22T10:00:00Z'));
    });
  });

  test('TrackException.toString includes the message', () {
    const exception = TrackException('Could not create track');
    expect(exception.toString(), 'TrackException: Could not create track');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_models_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/track_models.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/tracks/track_models.dart`:

```dart
class TrackPoint {
  const TrackPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class Track {
  const Track({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.points,
    required this.createdAt,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String name;
  final List<TrackPoint> points;
  final DateTime createdAt;

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
          ),
      ],
      createdAt: DateTime.parse(json['created_at'] as String),
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_models_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/track_models.dart app/test/tracks/track_models_test.dart
git commit -m "feat: add Track/TrackPoint model and TrackException"
```

---

## Task 4: `TracksRepository`

**Files:**
- Create: `app/lib/tracks/tracks_repository.dart`
- Test: `app/test/tracks/tracks_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (existing, `app/lib/api/api_client.dart`), `Track`/`TrackPoint`/`TrackException` (Task 3).
- Produces: `abstract class TracksRepository` with `list(String token) -> Future<List<Track>>` and `create(String token, {required String name, required List<TrackPoint> points}) -> Future<Track>`; `HttpTracksRepository implements TracksRepository`. Consumed by Task 5's `TracksController`.

Only `list`/`create` are built — no `get`/`update`/`delete`, since no UI in this slice exercises them (this slice has no track detail/edit/delete screens). Add them in a future track-management slice, the same way `waypoints`' repository grew its full method set only once each was UI-driven.

- [ ] **Step 1: Write the failing tests**

Create `app/test/tracks/tracks_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _trackJson = {
  'id': 't1',
  'org_id': 'o1',
  'owner_id': 'u1',
  'name': 'Morning walk',
  'geom': {
    'type': 'LineString',
    'coordinates': [
      [7.6, 45.9],
      [7.7, 46.0],
    ],
  },
  'created_at': '2026-08-22T10:00:00Z',
};

void main() {
  group('list', () {
    test('requests an explicit higher limit and returns parsed tracks on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/tracks');
          expect(request.url.queryParameters['limit'], '200');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({'items': [_trackJson], 'limit': 200, 'offset': 0}),
            200,
          );
        }),
      );
      final repo = HttpTracksRepository(client);

      final tracks = await repo.list('tok-1');

      expect(tracks, hasLength(1));
      expect(tracks.first.id, 't1');
    });

    test('throws TrackException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 500)),
      );
      final repo = HttpTracksRepository(client);

      await expectLater(repo.list('tok-1'), throwsA(isA<TrackException>()));
    });
  });

  group('create', () {
    test('sends name and [lng, lat] coordinates and returns the created track on 201', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/tracks');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_trackJson), 201);
        }),
      );
      final repo = HttpTracksRepository(client);

      final track = await repo.create(
        'tok-1',
        name: 'Morning walk',
        points: const [TrackPoint(lat: 45.9, lng: 7.6), TrackPoint(lat: 46.0, lng: 7.7)],
      );

      expect(track.id, 't1');
      expect(capturedBody, {
        'name': 'Morning walk',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9],
            [7.7, 46.0],
          ],
        },
      });
    });

    test('throws TrackException on non-201', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 422)),
      );
      final repo = HttpTracksRepository(client);

      await expectLater(
        repo.create('tok-1', name: 'x', points: const [TrackPoint(lat: 0, lng: 0), TrackPoint(lat: 1, lng: 1)]),
        throwsA(isA<TrackException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/tracks_repository_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/tracks_repository.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/tracks/tracks_repository.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'track_models.dart';

abstract class TracksRepository {
  Future<List<Track>> list(String token);

  Future<Track> create(String token, {required String name, required List<TrackPoint> points});
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
  Future<Track> create(String token, {required String name, required List<TrackPoint> points}) async {
    final response = await _client.post(
      '/tracks',
      token: token,
      body: {
        'name': name,
        'geom': {
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lng, p.lat],
          ],
        },
      },
    );
    if (response.statusCode != 201) {
      throw const TrackException('Could not create track');
    }
    return Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
```

Note: `list()` requests `?limit=200` explicitly from the start (the waypoints slice shipped without this and needed a follow-up fix once a final review caught the backend's silent 50-item default truncating older-first — doing it here from the start avoids repeating that).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/tracks_repository_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/tracks_repository.dart app/test/tracks/tracks_repository_test.dart
git commit -m "feat: add TracksRepository"
```

---

## Task 5: `TracksController`

**Files:**
- Create: `app/lib/tracks/tracks_controller.dart`
- Create: `app/test/tracks/fakes.dart`
- Test: `app/test/tracks/tracks_controller_test.dart`

**Interfaces:**
- Consumes: `TracksRepository`/`HttpTracksRepository` (Task 4), `Track`/`TrackPoint`/`TrackException` (Task 3), `apiClientProvider`/`tokenStorageProvider` (existing, `app/lib/auth/auth_controller.dart`).
- Produces: `tracksRepositoryProvider` (`Provider<TracksRepository>`), `tracksControllerProvider` (`NotifierProvider<TracksController, List<Track>>`), `TracksController` with `loadTracks()` and `saveTrack({required name, required points})`. Consumed by Task 8 (`MapScreen`).

- [ ] **Step 1: Add a fake repository for tests**

Create `app/test/tracks/fakes.dart`:

```dart
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_repository.dart';

class FakeTracksRepository implements TracksRepository {
  FakeTracksRepository({List<Track>? initial}) : items = List.of(initial ?? const []);

  final List<Track> items;

  /// Set to a Track for success, or a TrackException instance to throw.
  Object? createResult;

  @override
  Future<List<Track>> list(String token) async => List.of(items);

  @override
  Future<Track> create(String token, {required String name, required List<TrackPoint> points}) async {
    if (createResult is TrackException) throw createResult as TrackException;
    return createResult as Track;
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/tracks/tracks_controller_test.dart`:

```dart
import 'package:app/auth/token_storage.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

Track _track({String id = 't1', String name = 'Morning walk'}) {
  return Track(
    id: id,
    orgId: 'o1',
    ownerId: 'u1',
    name: name,
    points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
    createdAt: DateTime.utc(2026, 8, 22),
  );
}

ProviderContainer _buildContainer({
  required FakeTracksRepository repo,
  TokenStorage? storage,
}) {
  final tokenStorage = storage ?? (FakeTokenStorage()..write('tok-1'));
  return ProviderContainer(
    overrides: [
      tracksRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(tokenStorage),
    ],
  );
}

void main() {
  test('initial state is an empty list', () {
    final container = _buildContainer(repo: FakeTracksRepository());
    addTearDown(container.dispose);

    expect(container.read(tracksControllerProvider), isEmpty);
  });

  group('loadTracks', () {
    test('populates state from the repository', () async {
      final repo = FakeTracksRepository(initial: [_track()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(tracksControllerProvider.notifier).loadTracks();

      expect(container.read(tracksControllerProvider), hasLength(1));
    });

    test('leaves state empty when no token is stored', () async {
      final storage = FakeTokenStorage();
      final container = _buildContainer(repo: FakeTracksRepository(initial: [_track()]), storage: storage);
      addTearDown(container.dispose);

      await container.read(tracksControllerProvider.notifier).loadTracks();

      expect(container.read(tracksControllerProvider), isEmpty);
    });
  });

  group('saveTrack', () {
    test('appends the created track to state on success', () async {
      final repo = FakeTracksRepository()..createResult = _track(id: 'server-id');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(tracksControllerProvider.notifier).saveTrack(
            name: 'Morning walk',
            points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
          );

      final state = container.read(tracksControllerProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'server-id');
    });

    test('leaves state unchanged and rethrows on failure', () async {
      final repo = FakeTracksRepository()..createResult = const TrackException('Could not create track');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await expectLater(
        container.read(tracksControllerProvider.notifier).saveTrack(
              name: 'Morning walk',
              points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
            ),
        throwsA(isA<TrackException>()),
      );

      expect(container.read(tracksControllerProvider), isEmpty);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/tracks_controller_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/tracks_controller.dart` doesn't exist.

- [ ] **Step 4: Implement**

Create `app/lib/tracks/tracks_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart' show apiClientProvider, tokenStorageProvider;
import '../auth/token_storage.dart';
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
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> loadTracks() async {
    final token = await _storage.read();
    if (token == null) return;
    try {
      state = await _repository.list(token);
    } on TrackException {
      // Same intentional silent-swallow as WaypointsController.loadWaypoints():
      // an initial-load failure isn't surfaced in this slice.
    }
  }

  /// No optimistic insert: unlike a waypoint, a just-recorded track has no
  /// "immediately visible on the map" expectation before the user has even
  /// confirmed the save form, so there's nothing to roll back on failure —
  /// [TrackException] simply propagates to the caller.
  Future<void> saveTrack({required String name, required List<TrackPoint> points}) async {
    final token = await _storage.read();
    if (token == null) return;
    final created = await _repository.create(token, name: name, points: points);
    state = [...state, created];
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/tracks_controller_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/tracks/tracks_controller.dart app/test/tracks/fakes.dart app/test/tracks/tracks_controller_test.dart
git commit -m "feat: add TracksController"
```

---

## Task 6: `TrackRecordingController`

**Files:**
- Create: `app/lib/tracks/track_recording_controller.dart`
- Create: `app/test/tracks/fake_location_source.dart`
- Test: `app/test/tracks/track_recording_controller_test.dart`

**Interfaces:**
- Consumes: `LocationSource` (Task 2), `TrackPoint` (Task 3).
- Produces: `locationSourceProvider` (`Provider<LocationSource>`), `trackRecordingControllerProvider` (`NotifierProvider<TrackRecordingController, TrackRecordingState>`), sealed `TrackRecordingState` (`TrackRecordingIdle({errorMessage})` | `TrackRecordingActive({points, startedAt})`), `TrackRecordingController` with `start() -> Future<void>` and `stop() -> List<TrackPoint>`. Consumed by Task 8 (`MapScreen`).

- [ ] **Step 1: Add a fake location source for tests**

Create `app/test/tracks/fake_location_source.dart`:

```dart
import 'dart:async';

import 'package:app/tracks/location_source.dart';
import 'package:app/tracks/track_models.dart';

class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.permissionGranted = true});

  bool permissionGranted;
  final _controller = StreamController<TrackPoint>.broadcast();
  int? lastDistanceFilterMeters;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Stream<TrackPoint> positionStream({required int distanceFilterMeters}) {
    lastDistanceFilterMeters = distanceFilterMeters;
    return _controller.stream;
  }

  /// Test-only: simulates the device reporting a new position.
  void emit(TrackPoint point) => _controller.add(point);

  void dispose() => _controller.close();
}
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/tracks/track_recording_controller_test.dart`:

```dart
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location_source.dart';

void main() {
  test('initial state is idle', () {
    final source = FakeLocationSource();
    final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
    addTearDown(container.dispose);
    addTearDown(source.dispose);

    expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
  });

  group('start', () {
    test('transitions to active and requests a 10-meter distance filter', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      await container.read(trackRecordingControllerProvider.notifier).start();

      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingActive>());
      expect(source.lastDistanceFilterMeters, 10);
    });

    test('accumulates points as the location source emits them', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();

      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);
      source.emit(const TrackPoint(lat: 1.1, lng: 2.1));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(trackRecordingControllerProvider) as TrackRecordingActive;
      expect(state.points, hasLength(2));
      expect(state.points[0].lat, 1.0);
      expect(state.points[1].lat, 1.1);
    });

    test('stays idle with an error message when permission is denied', () async {
      final source = FakeLocationSource(permissionGranted: false);
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      await container.read(trackRecordingControllerProvider.notifier).start();

      final state = container.read(trackRecordingControllerProvider);
      expect(state, isA<TrackRecordingIdle>());
      expect((state as TrackRecordingIdle).errorMessage, isNotNull);
    });

    test('is a no-op when already recording', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);

      await container.read(trackRecordingControllerProvider.notifier).start();

      final state = container.read(trackRecordingControllerProvider) as TrackRecordingActive;
      expect(state.points, hasLength(1));
    });
  });

  group('stop', () {
    test('returns the accumulated points and transitions back to idle', () async {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);
      await container.read(trackRecordingControllerProvider.notifier).start();
      source.emit(const TrackPoint(lat: 1.0, lng: 2.0));
      await Future<void>.delayed(Duration.zero);
      source.emit(const TrackPoint(lat: 1.1, lng: 2.1));
      await Future<void>.delayed(Duration.zero);

      final points = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(points, hasLength(2));
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

    test('returns an empty list and is a no-op when already idle', () {
      final source = FakeLocationSource();
      final container = ProviderContainer(overrides: [locationSourceProvider.overrideWithValue(source)]);
      addTearDown(container.dispose);
      addTearDown(source.dispose);

      final points = container.read(trackRecordingControllerProvider.notifier).stop();

      expect(points, isEmpty);
      expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingIdle>());
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_recording_controller_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/track_recording_controller.dart` doesn't exist.

- [ ] **Step 4: Implement**

Create `app/lib/tracks/track_recording_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';
import 'track_models.dart';

sealed class TrackRecordingState {
  const TrackRecordingState();
}

class TrackRecordingIdle extends TrackRecordingState {
  const TrackRecordingIdle({this.errorMessage});

  final String? errorMessage;
}

class TrackRecordingActive extends TrackRecordingState {
  const TrackRecordingActive({required this.points, required this.startedAt});

  final List<TrackPoint> points;
  final DateTime startedAt;
}

final locationSourceProvider = Provider<LocationSource>((ref) => GeolocatorLocationSource());

final trackRecordingControllerProvider =
    NotifierProvider<TrackRecordingController, TrackRecordingState>(TrackRecordingController.new);

class TrackRecordingController extends Notifier<TrackRecordingState> {
  StreamSubscription<TrackPoint>? _subscription;

  @override
  TrackRecordingState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });
    return const TrackRecordingIdle();
  }

  LocationSource get _location => ref.read(locationSourceProvider);

  Future<void> start() async {
    if (state is TrackRecordingActive) return;
    final granted = await _location.ensurePermission();
    if (!granted) {
      state = const TrackRecordingIdle(
        errorMessage: 'Нужен доступ к геолокации, чтобы записать трек',
      );
      return;
    }
    state = TrackRecordingActive(points: const [], startedAt: DateTime.now());
    _subscription = _location.positionStream(distanceFilterMeters: 10).listen((point) {
      final current = state;
      if (current is! TrackRecordingActive) return;
      state = TrackRecordingActive(points: [...current.points, point], startedAt: current.startedAt);
    });
  }

  List<TrackPoint> stop() {
    final current = state;
    _subscription?.cancel();
    _subscription = null;
    state = const TrackRecordingIdle();
    return current is TrackRecordingActive ? current.points : const [];
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_recording_controller_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/tracks/track_recording_controller.dart app/test/tracks/fake_location_source.dart app/test/tracks/track_recording_controller_test.dart
git commit -m "feat: add TrackRecordingController"
```

---

## Task 7: Track name form bottom sheet

**Files:**
- Create: `app/lib/tracks/track_name_form_sheet.dart`
- Test: `app/test/tracks/track_name_form_sheet_test.dart`

**Interfaces:**
- Produces: `TrackNameFormResult({required name})`, `showTrackNameFormSheet(BuildContext context, {required String initialName}) -> Future<TrackNameFormResult?>`. Consumed by Task 8 (`MapScreen`).

- [ ] **Step 1: Write the failing tests**

Create `app/test/tracks/track_name_form_sheet_test.dart`:

```dart
import 'package:app/tracks/track_name_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(ValueChanged<TrackNameFormResult?> onResult) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await showTrackNameFormSheet(context, initialName: 'Трек 22.08.2026 15:30');
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pre-fills the initial name and save is disabled once cleared', (tester) async {
    TrackNameFormResult? result;
    await tester.pumpWidget(_harness((r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Трек 22.08.2026 15:30'), findsOneWidget);
    var saveButton = tester.widget<FilledButton>(find.byKey(const Key('track_save_button')));
    expect(saveButton.onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('track_name_field')), '');
    await tester.pump();
    saveButton = tester.widget<FilledButton>(find.byKey(const Key('track_save_button')));
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('track_name_field')), 'My hike');
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_save_button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'My hike');
  });

  testWidgets('returns null when dismissed without saving', (tester) async {
    TrackNameFormResult? result = const TrackNameFormResult(name: 'sentinel');
    await tester.pumpWidget(_harness((r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_name_form_sheet_test.dart` (from `app/`)
Expected: FAIL — `package:app/tracks/track_name_form_sheet.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `app/lib/tracks/track_name_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';

class TrackNameFormResult {
  const TrackNameFormResult({required this.name});

  final String name;
}

Future<TrackNameFormResult?> showTrackNameFormSheet(BuildContext context, {required String initialName}) {
  return showModalBottomSheet<TrackNameFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => TrackNameFormSheet(initialName: initialName),
  );
}

class TrackNameFormSheet extends StatefulWidget {
  const TrackNameFormSheet({super.key, required this.initialName});

  final String initialName;

  @override
  State<TrackNameFormSheet> createState() => _TrackNameFormSheetState();
}

class _TrackNameFormSheetState extends State<TrackNameFormSheet> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Сохранить трек', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('track_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('track_save_button'),
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      TrackNameFormResult(name: _nameController.text.trim()),
                    ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/tracks/track_name_form_sheet_test.dart` (from `app/`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/tracks/track_name_form_sheet.dart app/test/tracks/track_name_form_sheet_test.dart
git commit -m "feat: add track name/save bottom sheet"
```

---

## Task 8: Wire tracks into `MapScreen`

**Files:**
- Modify: `app/lib/map/map_screen.dart`
- Modify: `app/test/map/map_screen_test.dart`

**Interfaces:**
- Consumes: `tracksControllerProvider`/`tracksRepositoryProvider` (Task 5), `trackRecordingControllerProvider`/`TrackRecordingState`/`TrackRecordingActive`/`TrackRecordingIdle` (Task 6), `showTrackNameFormSheet`/`TrackNameFormResult` (Task 7), `TrackException`/`Track`/`TrackPoint` (Task 3).
- Produces: the finished user-facing feature — no further tasks consume this.

This task replaces `map_screen.dart`'s waypoint-only sync gate (`_isSyncing`/`_pendingWaypoints`/`_requestSync(waypoints)`/`_runSync(waypoints)`) with a unified, no-argument version that syncs both circles (waypoints) and lines (tracks) under one gate, since both are driven by `ref.listen` callbacks that can now fire independently (waypoints, saved tracks, and the in-progress recording are three separate state sources).

- [ ] **Step 1: Update the existing widget tests' provider overrides**

The existing tests in `app/test/map/map_screen_test.dart` will need `tracksRepositoryProvider` overridden once `MapScreen` starts reading `tracksControllerProvider`/`trackRecordingControllerProvider` (the latter needs no override — `locationSourceProvider`'s real `GeolocatorLocationSource` is never invoked unless `start()` is called, which none of the existing tests do). Replace the full contents of `app/test/map/map_screen_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

List<Override> _baseOverrides({
  required FakeAuthRepository authRepo,
  required FakeTokenStorage storage,
  FakeWaypointsRepository? waypointsRepo,
  FakeTracksRepository? tracksRepo,
}) {
  return [
    authRepositoryProvider.overrideWithValue(authRepo),
    tokenStorageProvider.overrideWithValue(storage),
    waypointsRepositoryProvider.overrideWithValue(waypointsRepo ?? FakeWaypointsRepository()),
    tracksRepositoryProvider.overrideWithValue(tracksRepo ?? FakeTracksRepository()),
  ];
}

void main() {
  testWidgets('MapScreen builds without throwing and shows a logout action', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(authRepo: repo, storage: storage),
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
      overrides: _baseOverrides(authRepo: repo, storage: storage),
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

  testWidgets('creating a waypoint via the controller updates the rendered state', (tester) async {
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
      overrides: _baseOverrides(authRepo: authRepo, storage: storage, waypointsRepo: waypointsRepo),
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
    // drives WaypointsController.createWaypoint directly (the same call
    // _onMapLongClick makes after the form is submitted) rather than
    // simulating a real long-press gesture on the (unrenderable) map
    // widget. This verifies the state MapScreen listens to updates
    // correctly; the long-press gesture itself is covered by manual
    // device verification (see Step 9 in the task brief).
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

  group('circleOptionsForWaypoint', () {
    Waypoint waypointWith({required String ownerId, required String type}) => Waypoint(
          id: 'w1',
          orgId: 'o1',
          ownerId: ownerId,
          name: 'Summit',
          type: type,
          note: null,
          lat: 1.0,
          lng: 2.0,
          canEdit: true,
          createdAt: DateTime.utc(2026, 8, 22),
        );

    test('falls back to the default type color for an unrecognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'not-a-real-type');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleColor, waypointTypeColors[defaultWaypointType]);
    });

    test('uses the type color for a recognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'danger');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleColor, waypointTypeColors['danger']);
    });

    test('own waypoints get a thin white stroke', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'generic');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleStrokeColor, '#FFFFFF');
      expect(options.circleStrokeWidth, 1);
    });

    test('shared waypoints get a thicker black stroke', () {
      final waypoint = waypointWith(ownerId: 'someone-else', type: 'generic');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleStrokeColor, '#000000');
      expect(options.circleStrokeWidth, 2);
    });
  });

  testWidgets('record toggle icon switches between start and stop', (tester) async {
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

    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
  });

  testWidgets('layers button opens a sheet with a tracks-visibility switch, off by default', (tester) async {
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

    await tester.tap(find.byKey(const Key('layers_button')));
    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byKey(const Key('tracks_visibility_switch')));
    expect(switchWidget.value, isFalse);
  });

  testWidgets('turning on the tracks-visibility switch loads tracks', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final authRepo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final tracksRepo = FakeTracksRepository();
    final container = ProviderContainer(
      overrides: _baseOverrides(authRepo: authRepo, storage: storage, tracksRepo: tracksRepo),
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
    expect(container.read(tracksControllerProvider), isEmpty);

    await tester.tap(find.byKey(const Key('layers_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tracks_visibility_switch')));
    await tester.pumpAndSettle();

    // loadTracks() ran (the fake repo starts empty, so state stays empty,
    // but this confirms the toggle triggered the load path without error).
    expect(container.read(tracksControllerProvider), isEmpty);
  });
}
```

- [ ] **Step 2: Run the existing tests to verify they still pass (with the overrides in place)**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/map/map_screen_test.dart` (from `app/`)
Expected: FAIL at this point — `package:app/tracks/tracks_controller.dart`'s `tracksRepositoryProvider` import resolves fine (Task 5 already merged), but the new tests reference `Icons.fiber_manual_record`/`layers_button`/`tracks_visibility_switch` which `MapScreen` doesn't produce yet (that's Step 3). The three pre-existing tests plus the `circleOptionsForWaypoint` group should already pass; only the three new tests at the bottom should fail. Confirm that specific split before proceeding.

- [ ] **Step 3: Implement — update `MapScreen`**

Replace the full contents of `app/lib/map/map_screen.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import '../tracks/track_models.dart';
import '../tracks/track_name_form_sheet.dart';
import '../tracks/track_recording_controller.dart';
import '../tracks/tracks_controller.dart';
import '../waypoints/waypoint_form_sheet.dart';
import '../waypoints/waypoint_models.dart';
import '../waypoints/waypoint_types.dart';
import '../waypoints/waypoints_controller.dart';

/// Pure mapping from a waypoint (plus the current user id, to distinguish
/// own vs. shared waypoints) to the [CircleOptions] used to render it.
/// Extracted as a top-level function so it can be unit-tested without a
/// real [MapLibreMapController]/platform view.
CircleOptions circleOptionsForWaypoint(Waypoint waypoint, String currentUserId) {
  final isOwn = waypoint.ownerId == currentUserId;
  return CircleOptions(
    geometry: LatLng(waypoint.lat, waypoint.lng),
    circleRadius: 8,
    circleColor: waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: isOwn ? '#FFFFFF' : '#000000',
    circleStrokeWidth: isOwn ? 1 : 2,
  );
}

const String _recordingLineKey = '__recording__';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  final Map<String, Circle> _circlesByWaypointId = {};
  final Map<String, Line> _linesByTrackId = {};
  bool _tracksVisible = false;

  // Serializes _syncCircles/_syncLines runs together: at most one combined
  // sync runs at a time, and any state change that arrives while a run is
  // in flight is coalesced into a single trailing re-run (rather than
  // racing concurrently against the in-flight one, which could orphan or
  // duplicate circles/lines).
  bool _isSyncing = false;
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(waypointsControllerProvider.notifier).loadWaypoints();
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onStyleLoaded() {
    // Every style (re)load disposes and re-creates maplibre_gl's annotation
    // managers, which wipes their internal id tracking. Drop our own
    // tracking too so the next sync re-adds every circle/line from scratch
    // instead of trying to update ids the new manager doesn't know about.
    _circlesByWaypointId.clear();
    _linesByTrackId.clear();
    _requestSync();
  }

  /// Entry point for requesting a combined circle+line sync. Coalesces
  /// concurrent requests so only one sync run is ever in flight; both
  /// [_syncCircles] and [_syncLines] read fresh state via `ref.read` when
  /// they actually run, rather than being handed a snapshot up front.
  void _requestSync() {
    if (_isSyncing) {
      _syncPending = true;
      return;
    }
    _runSync();
  }

  Future<void> _runSync() async {
    _isSyncing = true;
    try {
      await _syncCircles(ref.read(waypointsControllerProvider));
      await _syncLines();
    } catch (_) {
      // Swallow sync failures (e.g. a manager wasn't ready yet, or a style
      // reload raced with an in-flight call): the next state change or
      // style-loaded event will retry from a clean slate.
    } finally {
      _isSyncing = false;
    }
    if (_syncPending) {
      _syncPending = false;
      _requestSync();
    }
  }

  Future<void> _syncCircles(List<Waypoint> waypoints) async {
    final controller = _controller;
    // The circle manager is only initialized after onStyleLoadedCallback
    // fires; addCircle/updateCircle/removeCircle throw before then. A sync
    // can otherwise be requested (via the waypoints ref.listen callback,
    // once loadWaypoints() resolves) in the window after onMapCreated but
    // before the style has finished loading, so guard on both.
    if (controller == null || controller.circleManager == null) return;
    final currentUserId = _currentUserId();

    final currentIds = waypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
      }
    }

    for (final waypoint in waypoints) {
      final options = circleOptionsForWaypoint(waypoint, currentUserId);
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
      } else {
        await controller.updateCircle(existing, options);
      }
    }
  }

  Future<void> _syncLines() async {
    final controller = _controller;
    // Same readiness guard as _syncCircles, for the line manager.
    if (controller == null || controller.lineManager == null) return;

    final tracks = _tracksVisible ? ref.read(tracksControllerProvider) : const <Track>[];
    final currentIds = tracks.map((t) => t.id).toSet();
    for (final id in _linesByTrackId.keys.toList()) {
      if (id == _recordingLineKey) continue;
      if (!currentIds.contains(id)) {
        await controller.removeLine(_linesByTrackId.remove(id)!);
      }
    }

    for (final track in tracks) {
      final options = LineOptions(
        geometry: [for (final p in track.points) LatLng(p.lat, p.lng)],
        lineColor: '#1976D2',
        lineWidth: 3,
      );
      final existing = _linesByTrackId[track.id];
      if (existing == null) {
        _linesByTrackId[track.id] = await controller.addLine(options);
      } else {
        await controller.updateLine(existing, options);
      }
    }

    final recordingState = ref.read(trackRecordingControllerProvider);
    if (recordingState is TrackRecordingActive && recordingState.points.length >= 2) {
      final options = LineOptions(
        geometry: [for (final p in recordingState.points) LatLng(p.lat, p.lng)],
        lineColor: '#E53935',
        lineWidth: 4,
      );
      final existing = _linesByTrackId[_recordingLineKey];
      if (existing == null) {
        _linesByTrackId[_recordingLineKey] = await controller.addLine(options);
      } else {
        await controller.updateLine(existing, options);
      }
    } else {
      final existing = _linesByTrackId.remove(_recordingLineKey);
      if (existing != null) {
        await controller.removeLine(existing);
      }
    }
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
            Text(waypointTypeLabels[waypoint.type] ?? waypoint.type),
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
                    child: const Text('Изменить'),
                  ),
                  TextButton(
                    key: const Key('waypoint_delete_button'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Удалить'),
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
        title: const Text('Удалить метку?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Удалить')),
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

  String _defaultTrackName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Трек ${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
  }

  Future<void> _onRecordToggle(TrackRecordingState recordingState) async {
    if (recordingState is TrackRecordingActive) {
      final points = ref.read(trackRecordingControllerProvider.notifier).stop();
      if (points.length < 2) {
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
        await ref.read(tracksControllerProvider.notifier).saveTrack(name: result.name, points: points);
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

  Future<void> _onTracksVisibilityChanged(bool visible) async {
    setState(() => _tracksVisible = visible);
    if (visible && ref.read(tracksControllerProvider).isEmpty) {
      await ref.read(tracksControllerProvider.notifier).loadTracks();
    }
    _requestSync();
  }

  void _onLayersButtonPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Показывать треки'),
              Switch(
                key: const Key('tracks_visibility_switch'),
                value: _tracksVisible,
                onChanged: (value) {
                  setSheetState(() {});
                  _onTracksVisibilityChanged(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Waypoint>>(waypointsControllerProvider, (previous, next) {
      _requestSync();
    });
    ref.listen<List<Track>>(tracksControllerProvider, (previous, next) {
      _requestSync();
    });
    ref.listen<TrackRecordingState>(trackRecordingControllerProvider, (previous, next) {
      _requestSync();
    });

    final recordingState = ref.watch(trackRecordingControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
          IconButton(
            key: const Key('track_record_toggle'),
            icon: Icon(recordingState is TrackRecordingActive ? Icons.stop_circle : Icons.fiber_manual_record),
            onPressed: () => _onRecordToggle(recordingState),
          ),
          IconButton(
            key: const Key('layers_button'),
            icon: const Icon(Icons.layers),
            onPressed: _onLayersButtonPressed,
          ),
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

- [ ] **Step 4: Run the full map screen test file**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test test/map/map_screen_test.dart` (from `app/`)
Expected: PASS, all tests in the file green.

- [ ] **Step 5: Run the full frontend test suite**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat test` (from `app/`)
Expected: PASS, all tests across the whole suite green.

- [ ] **Step 6: Run static analysis**

Run: `C:\FlutterSDK\flutter\bin\flutter.bat analyze` (from `app/`)
Expected: no issues.

- [ ] **Step 7: Self-review the unified sync gate**

Confirm: `_syncCircles`/`_syncLines` are both called from the same `_runSync`, under the same `_isSyncing` flag; a `ref.listen` firing on any of the three providers (`waypointsControllerProvider`, `tracksControllerProvider`, `trackRecordingControllerProvider`) calls the same no-argument `_requestSync()`; `_onStyleLoaded` clears both `_circlesByWaypointId` and `_linesByTrackId` before resyncing. This mirrors the concurrency-safety properties the waypoints slice's fix round established for circles (readiness guard, clear-on-style-reload, serialized runs) — applied here to lines from the start, not discovered via a review fix loop.

- [ ] **Step 8: Manual verification on a real device (required — not covered by unit tests)**

Per this project's established practice (no working Android emulator on the dev machine), this step is the user's responsibility:
1. Rebuild the debug APK (with the LAN `API_BASE_URL` dart-define already set up in CI), install on a physical device.
2. Tap the record icon → grant the location permission prompt → confirm the icon switches to "stop" and a red line starts appearing on the map as you move.
3. Walk/drive a short distance → tap stop → confirm the name form appears pre-filled with a date/time → save → confirm the red recording line disappears.
4. Open the layers menu → toggle "Показывать треки" on → confirm the just-saved track appears as a blue line.
5. Toggle it off → confirm the blue line disappears; toggle on again → confirm it reappears without a second network request (already cached in `TracksController`'s state).
6. Try recording and stopping immediately (fewer than 2 points) → confirm the "too short to save" message appears and no save form opens.
7. Deny the location permission when prompted → confirm an error message appears and recording does not start.

- [ ] **Step 9: Commit**

```bash
git add app/lib/map/map_screen.dart app/test/map/map_screen_test.dart
git commit -m "feat: record, save, and toggle visibility of tracks on the map"
```

---

## Final review

After Task 8, run the full regression check before considering the slice done:

```bash
cd app && C:\FlutterSDK\flutter\bin\flutter.bat analyze && C:\FlutterSDK\flutter\bin\flutter.bat test
```

```bash
docker compose exec api pytest -q
```

Both must be fully green (the backend suite should be unaffected — this slice makes no backend changes — but re-running it costs nothing and confirms that's actually true). Per this project's established practice, also do a final whole-branch review before merging, even though this was built as a single slice/branch.
