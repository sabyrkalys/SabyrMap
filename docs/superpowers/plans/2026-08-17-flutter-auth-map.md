# Flutter Frontend: Auth + Empty Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Flutter (Android) frontend slice — register/login screens against the existing `/auth/*` API, secure token storage with auto-login on app start, and an empty MapLibre Native map screen using the OpenFreeMap public vector style.

**Architecture:** A new Flutter app at `app/`, alongside the existing `api/`. Riverpod holds session state (`AuthController`, a `Notifier<AuthState>`) backed by an `AuthRepository` (HTTP calls via a thin `ApiClient`) and a `TokenStorage` (Android-Keystore-backed via `flutter_secure_storage`). `LoginScreen`/`RegisterScreen` drive the controller; on success, `MapScreen` renders a `maplibre_gl` map with no data layers yet.

**Tech Stack:** Flutter (stable, installed at `C:\FlutterSDK\flutter`), `flutter_riverpod`, `http`, `flutter_secure_storage`, `maplibre_gl`.

**Spec:** `docs/superpowers/specs/2026-08-17-flutter-auth-map-design.md`

## Global Constraints

- Android is the only build target this slice targets (`flutter create --platforms=android`). Package ID: `com.alpinequest.app`.
- `POST /auth/register`: `{email, password}` → `200 {access_token, token_type}` / `409 {"detail":"Email already registered"}` / `422` (validation).
- `POST /auth/login`: `{email, password}` → `200 {access_token, token_type}` / `401 {"detail":"Invalid email or password"}` / `422`.
- `GET /auth/me`: header `Authorization: Bearer <token>` → `200 {id, email, role, org_id}` / `401 {"detail":"Could not validate credentials"}`.
- No refresh-token flow — a single 24h JWT; any 401 (including the bootstrap `/auth/me` check) routes back to `LoginScreen` and clears the stored token.
- API base URL: compile-time `--dart-define=API_BASE_URL=...`, default `http://10.0.2.2:8000` (Android emulator's alias for host `localhost`, where `docker-compose`'s `api` service listens).
- Map style: `https://tiles.openfreemap.org/styles/liberty` (no API key, no offline tiles this slice).
- No `go_router` — plain `Navigator` with named routes (`/login`, `/register`, `/map`).
- Auth/network errors render as inline text under the form, not a dialog.
- No live emulator/device verification is possible in this environment (reproducible `qemu` crash on this machine, cause undetermined) — every task's automated tests (`flutter analyze`, `flutter test`) are the verification gate here; real-device verification is manual, by the user, after implementation.

---

## File Structure

```
app/
  pubspec.yaml
  android/app/src/main/AndroidManifest.xml   # modified: INTERNET permission, cleartext traffic
  lib/
    main.dart                # MaterialApp, routes, ProviderScope, AuthGate
    config.dart               # AppConfig.apiBaseUrl, AppConfig.mapStyleUrl
    api/
      api_client.dart         # ApiClient: get/post over package:http
    auth/
      auth_models.dart        # AuthUser, AuthException
      token_storage.dart      # TokenStorage (interface) + SecureTokenStorage
      auth_repository.dart    # AuthRepository (interface) + HttpAuthRepository
      auth_controller.dart    # AuthState, AuthController, providers
      login_screen.dart
      register_screen.dart
    map/
      map_screen.dart         # MapLibreMap with OpenFreeMap style
  test/
    auth/
      fakes.dart               # FakeTokenStorage, FakeAuthRepository (shared test doubles)
      token_storage_test.dart
      auth_repository_test.dart
      auth_controller_test.dart
      login_screen_test.dart
      register_screen_test.dart
    api/
      api_client_test.dart
    map/
      map_screen_test.dart
```

---

### Task 1: Project scaffold, dependencies, Android manifest

**Files:**
- Create: `app/` (via `flutter create`)
- Create: `app/lib/config.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/pubspec.yaml` (via `flutter pub add`)

**Interfaces:**
- Produces: `AppConfig.apiBaseUrl` (`String`), `AppConfig.mapStyleUrl` (`String`) — every later task that talks to the API or renders the map reads these.

- [ ] **Step 1: Scaffold the Flutter project**

From the repo root:

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" create --platforms=android --org com.alpinequest --project-name app app
```

This generates a full default Flutter app (default counter `lib/main.dart`, default `test/widget_test.dart`, `android/` project). Later tasks overwrite `lib/main.dart`; Task 8 replaces the default test.

- [ ] **Step 2: Add dependencies**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" pub add flutter_riverpod http flutter_secure_storage maplibre_gl
```

This resolves and pins current compatible versions in `pubspec.yaml`/`pubspec.lock` — do not hand-edit version numbers.

- [ ] **Step 3: Add Android manifest permissions**

Open `app/android/app/src/main/AndroidManifest.xml`. Add the INTERNET permission as a direct child of `<manifest>`, before `<application>`:

```xml
    <uses-permission android:name="android.permission.INTERNET" />
```

On the `<application ...>` tag, add `android:usesCleartextTraffic="true"` (the dev `API_BASE_URL` default is plain `http://`, which Android blocks by default since API 28):

```xml
    <application
        android:label="app"
        android:usesCleartextTraffic="true"
        android:icon="@mipmap/ic_launcher">
```

(Keep whatever other attributes `flutter create` already generated on that tag — only add `android:usesCleartextTraffic="true"`.)

- [ ] **Step 4: Create the config file**

Create `app/lib/config.dart`:

```dart
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String mapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';
}
```

- [ ] **Step 5: Verify the scaffold builds and analyzes cleanly**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" analyze
```

Expected: `No issues found!` (the default counter app and `config.dart` both analyze clean).

- [ ] **Step 6: Commit**

```bash
cd ..
git add app
git commit -m "chore: scaffold Flutter app with dependencies and Android manifest config"
```

---

### Task 2: `ApiClient`

**Files:**
- Create: `app/lib/api/api_client.dart`
- Test: `app/test/api/api_client_test.dart`

**Interfaces:**
- Consumes: `AppConfig.apiBaseUrl` (Task 1)
- Produces: `class ApiClient { ApiClient({required String baseUrl, http.Client? httpClient}); Future<http.Response> get(String path, {String? token}); Future<http.Response> post(String path, {Map<String, dynamic>? body, String? token}); }` — `AuthRepository` (Task 4) is built on this.

- [ ] **Step 1: Write the failing tests**

Create `app/test/api/api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('get sends request to baseUrl + path with no auth header when token is null', () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.get('/auth/me');

    expect(capturedUri, Uri.parse('http://example.test/auth/me'));
    expect(capturedHeaders!.containsKey('Authorization'), isFalse);
  });

  test('get attaches Authorization header when token is provided', () async {
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.get('/auth/me', token: 'abc123');

    expect(capturedHeaders!['Authorization'], 'Bearer abc123');
  });

  test('post sends JSON-encoded body with Content-Type header', () async {
    String? capturedBody;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.post('/auth/login', body: {'email': 'a@b.test', 'password': 'secret'});

    expect(jsonDecode(capturedBody!), {'email': 'a@b.test', 'password': 'secret'});
    expect(capturedHeaders!['Content-Type'], contains('application/json'));
  });

  test('post with no body sends an empty JSON object', () async {
    String? capturedBody;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.post('/auth/logout');

    expect(capturedBody, '{}');
  });

  test('returns the underlying response unchanged', () async {
    final mockClient = MockClient((request) async => http.Response('{"ok":true}', 201));
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    final response = await client.post('/auth/register');

    expect(response.statusCode, 201);
    expect(response.body, '{"ok":true}');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/api/api_client_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/api/api_client.dart'`.

- [ ] **Step 3: Implement**

Create `app/lib/api/api_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Future<http.Response> get(String path, {String? token}) {
    return _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body, String? token}) {
    return _httpClient.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body ?? const {}),
    );
  }

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/api/api_client_test.dart
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd ..
git add app/lib/api/api_client.dart app/test/api/api_client_test.dart
git commit -m "feat: add ApiClient HTTP wrapper"
```

---

### Task 3: `TokenStorage`

**Files:**
- Create: `app/lib/auth/token_storage.dart`
- Create: `app/test/auth/fakes.dart`
- Test: `app/test/auth/token_storage_test.dart`

**Interfaces:**
- Produces: `abstract class TokenStorage { Future<String?> read(); Future<void> write(String token); Future<void> delete(); }`, `class SecureTokenStorage implements TokenStorage` (production, Android-Keystore-backed via `flutter_secure_storage`), `class FakeTokenStorage implements TokenStorage` (in-memory, in `test/auth/fakes.dart` — Tasks 5-7 import this for their tests).

`SecureTokenStorage` wraps a real platform plugin with no branching logic of its own — it is not independently unit-tested here (platform-channel mocking for a 1:1 delegating wrapper is not worth the weight; see Global Constraints on manual verification). `FakeTokenStorage` **is** production test-support code with real logic (in-memory state), and gets the full TDD cycle.

- [ ] **Step 1: Write the failing test**

Create `app/test/auth/fakes.dart`:

```dart
import 'package:app/auth/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async {
    _token = token;
  }

  @override
  Future<void> delete() async {
    _token = null;
  }
}
```

Create `app/test/auth/token_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('read returns null before anything is written', () async {
    final storage = FakeTokenStorage();

    expect(await storage.read(), isNull);
  });

  test('write then read returns the stored token', () async {
    final storage = FakeTokenStorage();

    await storage.write('token-123');

    expect(await storage.read(), 'token-123');
  });

  test('delete clears the stored token', () async {
    final storage = FakeTokenStorage();
    await storage.write('token-123');

    await storage.delete();

    expect(await storage.read(), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/token_storage_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/auth/token_storage.dart'`.

- [ ] **Step 3: Implement**

Create `app/lib/auth/token_storage.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) => _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/token_storage_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd ..
git add app/lib/auth/token_storage.dart app/test/auth/fakes.dart app/test/auth/token_storage_test.dart
git commit -m "feat: add TokenStorage interface, SecureTokenStorage, and FakeTokenStorage test double"
```

---

### Task 4: Auth models and `AuthRepository`

**Files:**
- Create: `app/lib/auth/auth_models.dart`
- Create: `app/lib/auth/auth_repository.dart`
- Test: `app/test/auth/auth_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task 2)
- Produces: `class AuthUser { const AuthUser({required String id, required String email, required String role, required String orgId}); }`, `class AuthException implements Exception { const AuthException(String message); final String message; }`, `abstract class AuthRepository { Future<String> register(String email, String password); Future<String> login(String email, String password); Future<AuthUser> me(String token); }`, `class HttpAuthRepository implements AuthRepository` — `AuthController` (Task 5) depends on the `AuthRepository` interface.

- [ ] **Step 1: Write the failing tests**

Create `app/test/auth/auth_repository_test.dart`:

```dart
import 'package:app/api/api_client.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('register', () {
    test('returns the access token on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/register');
          return http.Response('{"access_token":"tok-1","token_type":"bearer"}', 200);
        }),
      );
      final repo = HttpAuthRepository(client);

      final token = await repo.register('a@b.test', 'secret123');

      expect(token, 'tok-1');
    });

    test('throws AuthException("Email already registered") on 409', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Email already registered"}', 409)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(
        repo.register('a@b.test', 'secret123'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Email already registered')),
      );
    });

    test('throws AuthException on 422', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"validation error"}', 422)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(repo.register('bad', ''), throwsA(isA<AuthException>()));
    });
  });

  group('login', () {
    test('returns the access token on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/login');
          return http.Response('{"access_token":"tok-2","token_type":"bearer"}', 200);
        }),
      );
      final repo = HttpAuthRepository(client);

      final token = await repo.login('a@b.test', 'secret123');

      expect(token, 'tok-2');
    });

    test('throws AuthException("Invalid email or password") on 401', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Invalid email or password"}', 401)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(
        repo.login('a@b.test', 'wrong'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Invalid email or password')),
      );
    });
  });

  group('me', () {
    test('returns an AuthUser on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/me');
          expect(request.headers['Authorization'], 'Bearer tok-3');
          return http.Response(
            '{"id":"11111111-1111-1111-1111-111111111111","email":"a@b.test","role":"owner","org_id":"22222222-2222-2222-2222-222222222222"}',
            200,
          );
        }),
      );
      final repo = HttpAuthRepository(client);

      final user = await repo.me('tok-3');

      expect(user.id, '11111111-1111-1111-1111-111111111111');
      expect(user.email, 'a@b.test');
      expect(user.role, 'owner');
      expect(user.orgId, '22222222-2222-2222-2222-222222222222');
    });

    test('throws AuthException on 401', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Could not validate credentials"}', 401)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(repo.me('bad-token'), throwsA(isA<AuthException>()));
    });
  });

  test('network failure surfaces as AuthException', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async => throw const SocketExceptionStub()),
    );
    final repo = HttpAuthRepository(client);

    await expectLater(repo.login('a@b.test', 'secret123'), throwsA(isA<AuthException>()));
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/auth_repository_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/auth/auth_repository.dart'` (and `auth_models.dart`).

- [ ] **Step 3: Implement the models**

Create `app/lib/auth/auth_models.dart`:

```dart
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.orgId,
  });

  final String id;
  final String email;
  final String role;
  final String orgId;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
```

- [ ] **Step 4: Implement the repository**

Create `app/lib/auth/auth_repository.dart`:

```dart
import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'auth_models.dart';

abstract class AuthRepository {
  Future<String> register(String email, String password);
  Future<String> login(String email, String password);
  Future<AuthUser> me(String token);
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<String> register(String email, String password) {
    return _postForToken('/auth/register', email, password, messageForStatus: (status) {
      if (status == 409) return 'Email already registered';
      return 'Please check your email and password';
    });
  }

  @override
  Future<String> login(String email, String password) {
    return _postForToken('/auth/login', email, password, messageForStatus: (status) {
      if (status == 401) return 'Invalid email or password';
      return 'Please check your email and password';
    });
  }

  Future<String> _postForToken(
    String path,
    String email,
    String password, {
    required String Function(int statusCode) messageForStatus,
  }) async {
    try {
      final response = await _client.post(path, body: {'email': email, 'password': password});
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['access_token'] as String;
      }
      throw AuthException(messageForStatus(response.statusCode));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not connect');
    }
  }

  @override
  Future<AuthUser> me(String token) async {
    try {
      final response = await _client.get('/auth/me', token: token);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AuthUser(
          id: json['id'] as String,
          email: json['email'] as String,
          role: json['role'] as String,
          orgId: json['org_id'] as String,
        );
      }
      throw const AuthException('Could not validate credentials');
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not connect');
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/auth_repository_test.dart
```

Expected: all 8 tests PASS.

- [ ] **Step 6: Commit**

```bash
cd ..
git add app/lib/auth/auth_models.dart app/lib/auth/auth_repository.dart app/test/auth/auth_repository_test.dart
git commit -m "feat: add auth models and HttpAuthRepository"
```

---

### Task 5: `AuthController` and providers

**Files:**
- Create: `app/lib/auth/auth_controller.dart`
- Modify: `app/test/auth/fakes.dart` (add `FakeAuthRepository`)
- Test: `app/test/auth/auth_controller_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`, `AuthUser`, `AuthException` (Task 4); `TokenStorage`, `FakeTokenStorage` (Task 3)
- Produces: `sealed class AuthState`, `AuthUnauthenticated({String? errorMessage})`, `AuthAuthenticating()`, `AuthAuthenticated(AuthUser user)`, `class AuthController extends Notifier<AuthState> { Future<void> bootstrap(); Future<void> login(String email, String password); Future<void> register(String email, String password); Future<void> logout(); }`, `final authRepositoryProvider = Provider<AuthRepository>(...)`, `final tokenStorageProvider = Provider<TokenStorage>(...)`, `final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new)` — `LoginScreen`/`RegisterScreen`/`MapScreen`/`main.dart` (Tasks 6-8) all depend on `authControllerProvider` and the `AuthState` variants.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/auth/fakes.dart` (append below `FakeTokenStorage`):

```dart
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.registerResult,
    this.loginResult,
    this.meResult,
  });

  /// Set to a token String for success, or an AuthException instance to throw.
  Object? registerResult;
  Object? loginResult;
  Object? meResult;

  String? lastRegisterEmail;
  String? lastLoginEmail;
  String? lastMeToken;

  @override
  Future<String> register(String email, String password) async {
    lastRegisterEmail = email;
    if (registerResult is AuthException) throw registerResult as AuthException;
    return registerResult as String;
  }

  @override
  Future<String> login(String email, String password) async {
    lastLoginEmail = email;
    if (loginResult is AuthException) throw loginResult as AuthException;
    return loginResult as String;
  }

  @override
  Future<AuthUser> me(String token) async {
    lastMeToken = token;
    if (meResult is AuthException) throw meResult as AuthException;
    return meResult as AuthUser;
  }
}
```

(The full file now has both the existing `FakeTokenStorage` class and this new import block + `FakeAuthRepository` class — put the two new imports at the top of the file alongside the existing `token_storage.dart` import.)

Create `app/test/auth/auth_controller_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');

ProviderContainer _buildContainer({
  required FakeAuthRepository repo,
  required FakeTokenStorage storage,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(storage),
    ],
  );
}

void main() {
  test('initial state is AuthUnauthenticated', () {
    final container = _buildContainer(repo: FakeAuthRepository(), storage: FakeTokenStorage());
    addTearDown(container.dispose);

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  group('bootstrap', () {
    test('stays AuthUnauthenticated when no token is stored', () async {
      final container = _buildContainer(repo: FakeAuthRepository(), storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('becomes AuthAuthenticated when a stored token validates', () async {
      final storage = FakeTokenStorage();
      await storage.write('tok-1');
      final repo = FakeAuthRepository(meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'a@b.test');
      expect(repo.lastMeToken, 'tok-1');
    });

    test('clears the token and becomes AuthUnauthenticated when the stored token is invalid', () async {
      final storage = FakeTokenStorage();
      await storage.write('bad-token');
      final repo = FakeAuthRepository(meResult: const AuthException('Could not validate credentials'));
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
      expect(await storage.read(), isNull);
    });
  });

  group('login', () {
    test('on success stores the token and becomes AuthAuthenticated', () async {
      final storage = FakeTokenStorage();
      final repo = FakeAuthRepository(loginResult: 'tok-2', meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login('a@b.test', 'secret123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(await storage.read(), 'tok-2');
    });

    test('on failure becomes AuthUnauthenticated carrying the error message', () async {
      final repo = FakeAuthRepository(loginResult: const AuthException('Invalid email or password'));
      final container = _buildContainer(repo: repo, storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login('a@b.test', 'wrong');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect((state as AuthUnauthenticated).errorMessage, 'Invalid email or password');
    });
  });

  group('register', () {
    test('on success stores the token and becomes AuthAuthenticated', () async {
      final storage = FakeTokenStorage();
      final repo = FakeAuthRepository(registerResult: 'tok-3', meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).register('a@b.test', 'secret123');

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect(await storage.read(), 'tok-3');
    });

    test('on failure becomes AuthUnauthenticated carrying the error message', () async {
      final repo = FakeAuthRepository(registerResult: const AuthException('Email already registered'));
      final container = _buildContainer(repo: repo, storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).register('a@b.test', 'secret123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect((state as AuthUnauthenticated).errorMessage, 'Email already registered');
    });
  });

  test('logout clears the token and becomes AuthUnauthenticated', () async {
    final storage = FakeTokenStorage();
    await storage.write('tok-4');
    final repo = FakeAuthRepository(meResult: _user);
    final container = _buildContainer(repo: repo, storage: storage);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(await storage.read(), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/auth_controller_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/auth/auth_controller.dart'`.

- [ ] **Step 3: Implement**

Create `app/lib/auth/auth_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.errorMessage});

  final String? errorMessage;
}

class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.apiBaseUrl);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return HttpAuthRepository(ref.watch(apiClientProvider));
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnauthenticated();

  AuthRepository get _repository => ref.read(authRepositoryProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> bootstrap() async {
    final token = await _storage.read();
    if (token == null) {
      state = const AuthUnauthenticated();
      return;
    }
    state = const AuthAuthenticating();
    try {
      final user = await _repository.me(token);
      state = AuthAuthenticated(user);
    } on AuthException {
      await _storage.delete();
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) => _authenticate(
        () => _repository.login(email, password),
      );

  Future<void> register(String email, String password) => _authenticate(
        () => _repository.register(email, password),
      );

  Future<void> _authenticate(Future<String> Function() obtainToken) async {
    state = const AuthAuthenticating();
    try {
      final token = await obtainToken();
      final user = await _repository.me(token);
      await _storage.write(token);
      state = AuthAuthenticated(user);
    } on AuthException catch (e) {
      state = AuthUnauthenticated(errorMessage: e.message);
    }
  }

  Future<void> logout() async {
    await _storage.delete();
    state = const AuthUnauthenticated();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/auth_controller_test.dart
```

Expected: all 9 tests PASS.

- [ ] **Step 5: Run the full test suite so far**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test
```

Expected: all tests across `test/api/`, `test/auth/` PASS (the default `test/widget_test.dart` from Task 1 also still passes, untouched).

- [ ] **Step 6: Commit**

```bash
cd ..
git add app/lib/auth/auth_controller.dart app/test/auth/fakes.dart app/test/auth/auth_controller_test.dart
git commit -m "feat: add AuthController state machine and Riverpod providers"
```

---

### Task 6: `LoginScreen`

**Files:**
- Create: `app/lib/auth/login_screen.dart`
- Test: `app/test/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `authControllerProvider`, `AuthState`, `AuthUnauthenticated`, `AuthAuthenticating`, `AuthAuthenticated` (Task 5); `FakeAuthRepository`, `FakeTokenStorage` (Task 3/5, via `fakes.dart`)
- Produces: `class LoginScreen extends ConsumerStatefulWidget` — `main.dart` (Task 8) routes `/login` to this. Navigates to `/map` via `Navigator.pushReplacementNamed` when `ref.watch(authControllerProvider)` becomes `AuthAuthenticated`. Navigates to `/register` via a "Create account" `TextButton`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/auth/login_screen_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _wrap({required FakeAuthRepository repo, required FakeTokenStorage storage}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(storage),
    ],
    child: const MaterialApp(
      home: LoginScreen(),
      routes: {'/register': _RegisterStub.route, '/map': _MapStub.route},
    ),
  );
}

class _RegisterStub extends StatelessWidget {
  const _RegisterStub();
  static Widget route(BuildContext context) => const _RegisterStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('register screen'));
}

class _MapStub extends StatelessWidget {
  const _MapStub();
  static Widget route(BuildContext context) => const _MapStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('map screen'));
}

void main() {
  testWidgets('submit button is disabled until both fields are non-empty', (tester) async {
    await tester.pumpWidget(_wrap(repo: FakeAuthRepository(), storage: FakeTokenStorage()));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();

    final enabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('shows the error message and stays on the screen on failure', (tester) async {
    final repo = FakeAuthRepository(loginResult: const AuthException('Invalid email or password'));
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'wrong');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('navigates to /map on successful login', (tester) async {
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(loginResult: 'tok-1', meResult: user);
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('map screen'), findsOneWidget);
  });

  testWidgets('tapping "Create account" navigates to /register', (tester) async {
    await tester.pumpWidget(_wrap(repo: FakeAuthRepository(), storage: FakeTokenStorage()));

    await tester.tap(find.byKey(const Key('login_create_account_button')));
    await tester.pumpAndSettle();

    expect(find.text('register screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/login_screen_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/auth/login_screen.dart'`.

- [ ] **Step 3: Implement**

Create `app/lib/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        Navigator.of(context).pushReplacementNamed('/map');
      }
    });

    final state = ref.watch(authControllerProvider);
    final isLoading = state is AuthAuthenticating;
    final errorMessage = state is AuthUnauthenticated ? state.errorMessage : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('login_email_field'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login_password_field'),
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ElevatedButton(
              onPressed: isLoading || !_canSubmit
                  ? null
                  : () => ref.read(authControllerProvider.notifier).login(
                        _emailController.text,
                        _passwordController.text,
                      ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log in'),
            ),
            TextButton(
              key: const Key('login_create_account_button'),
              onPressed: () => Navigator.of(context).pushNamed('/register'),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/login_screen_test.dart
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd ..
git add app/lib/auth/login_screen.dart app/test/auth/login_screen_test.dart
git commit -m "feat: add LoginScreen"
```

---

### Task 7: `RegisterScreen`

**Files:**
- Create: `app/lib/auth/register_screen.dart`
- Test: `app/test/auth/register_screen_test.dart`

**Interfaces:**
- Consumes: same `AuthState`/`authControllerProvider` surface as Task 6.
- Produces: `class RegisterScreen extends ConsumerStatefulWidget` — `main.dart` (Task 8) routes `/register` to this. Same navigation shape as `LoginScreen`, mirrored for `register()` instead of `login()`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/auth/register_screen_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _wrap({required FakeAuthRepository repo, required FakeTokenStorage storage}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(storage),
    ],
    child: const MaterialApp(
      home: RegisterScreen(),
      routes: {'/map': _MapStub.route},
    ),
  );
}

class _MapStub extends StatelessWidget {
  const _MapStub();
  static Widget route(BuildContext context) => const _MapStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('map screen'));
}

void main() {
  testWidgets('submit button is disabled until both fields are non-empty', (tester) async {
    await tester.pumpWidget(_wrap(repo: FakeAuthRepository(), storage: FakeTokenStorage()));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.pump();

    final enabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('shows the error message and stays on the screen on failure', (tester) async {
    final repo = FakeAuthRepository(registerResult: const AuthException('Email already registered'));
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Email already registered'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('navigates to /map on successful registration', (tester) async {
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(registerResult: 'tok-1', meResult: user);
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('map screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/register_screen_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/auth/register_screen.dart'`.

- [ ] **Step 3: Implement**

Create `app/lib/auth/register_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        Navigator.of(context).pushReplacementNamed('/map');
      }
    });

    final state = ref.watch(authControllerProvider);
    final isLoading = state is AuthAuthenticating;
    final errorMessage = state is AuthUnauthenticated ? state.errorMessage : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('register_email_field'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('register_password_field'),
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ElevatedButton(
              onPressed: isLoading || !_canSubmit
                  ? null
                  : () => ref.read(authControllerProvider.notifier).register(
                        _emailController.text,
                        _passwordController.text,
                      ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/auth/register_screen_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd ..
git add app/lib/auth/register_screen.dart app/test/auth/register_screen_test.dart
git commit -m "feat: add RegisterScreen"
```

---

### Task 8: `MapScreen`, `main.dart`, and final wiring

**Files:**
- Create: `app/lib/map/map_screen.dart`
- Modify: `app/lib/main.dart` (replace the default counter app)
- Delete: `app/test/widget_test.dart` (default counter-app test, no longer applicable)
- Test: `app/test/map/map_screen_test.dart`

**Interfaces:**
- Consumes: `AppConfig.mapStyleUrl` (Task 1); `authControllerProvider`, `AuthState` variants (Task 5); `LoginScreen`, `RegisterScreen` (Tasks 6-7)
- Produces: `class MapScreen extends ConsumerWidget` (with a logout button); `main()` wiring `ProviderScope` + `MaterialApp` with routes `/login`, `/register`, `/map`, and an `AuthGate` home widget that calls `bootstrap()` once and shows `LoginScreen` or `MapScreen` depending on `AuthState`.

- [ ] **Step 1: Write the failing test**

Create `app/test/map/map_screen_test.dart`:

```dart
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/map/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';

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

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/map/map_screen_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:app/map/map_screen.dart'`.

- [ ] **Step 3: Implement `MapScreen`**

Create `app/lib/map/map_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test test/map/map_screen_test.dart
```

Expected: both tests PASS.

- [ ] **Step 5: Replace `main.dart` with the routed app**

Delete the default `app/test/widget_test.dart` (it exercises the default counter app removed in this step).

Replace `app/lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'map/map_screen.dart';

void main() {
  runApp(const ProviderScope(child: AlpineQuestApp()));
}

class AlpineQuestApp extends StatelessWidget {
  const AlpineQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlpineQuest',
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/map': (context) => const MapScreen(),
      },
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return switch (state) {
      AuthAuthenticated() => const MapScreen(),
      AuthAuthenticating() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthUnauthenticated() => const LoginScreen(),
    };
  }
}
```

- [ ] **Step 6: Run the full test suite**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" test
```

Expected: every test across `test/api/`, `test/auth/`, `test/map/` PASSES, no regressions.

- [ ] **Step 7: Run static analysis**

```bash
"C:\FlutterSDK\flutter\bin\flutter.bat" analyze
```

Expected: `No issues found!`.

- [ ] **Step 8: Commit**

```bash
cd ..
git add app/lib/map/map_screen.dart app/lib/main.dart app/test/map/map_screen_test.dart
git rm app/test/widget_test.dart
git commit -m "feat: add MapScreen and wire up routed app with AuthGate"
```

---

## Manual verification (after the plan is implemented)

This environment's Android emulator does not currently boot (reproducible `qemu` crash, cause undetermined — not fixed by disabling hardware acceleration or switching API levels). Once this plan lands, verify on a real device or a working emulator:

```bash
cd app
"C:\FlutterSDK\flutter\bin\flutter.bat" run --dart-define=API_BASE_URL=http://<host-ip>:8000
```

(Use `10.0.2.2` instead of `<host-ip>` if running on the Android emulator once one is available; use the host machine's LAN IP for a physical device.) With the backend running (`docker-compose up` from the repo root), confirm: register a new account → lands on the map screen with OpenFreeMap tiles visible; log out → back to login; log back in with the same credentials → map screen again; kill and restart the app → auto-login straight to the map screen (bootstrap flow).
