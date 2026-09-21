# Remove client auth, single implicit user — design

Date: 2026-09-21

## Goal

Remove the login/registration flow and token handling from the Flutter app. Access
protection moves outside the app (a VPN-like application); the backend serves every
request as one fixed user.

## Decisions

- Approach: backend change + full client cleanup (chosen over "client-only silent
  auto-login", which would leave credentials baked into the APK).
- Roles, sharing and token-based auth stay in the backend, disabled by default, so
  existing multi-user tests and future v2 work are unaffected.
- The existing dev account (`alpinequest.dev@example.com`) is reused as the single
  user, so existing waypoints/tracks keep their owner.
- Settings tab stays as an empty screen (placeholder for future settings).

## Backend (`api/`)

- `Settings`: add `AUTH_DISABLED: bool = False` and
  `SINGLE_USER_EMAIL: str = "alpinequest.dev@example.com"`.
- `get_current_user` (`app/dependencies.py`): when `AUTH_DISABLED` is true, ignore the
  `Authorization` header. Look up the active user by `SINGLE_USER_EMAIL`; if absent,
  create it via `create_personal_organization_and_owner` with a password hash no
  password can match. Always return that user.
- When `AUTH_DISABLED` is false, behaviour is unchanged.
- `/auth/*` endpoints stay; the client no longer uses them.
- `docker-compose.yml`: set `AUTH_DISABLED: "true"` for the `api` service.
- New tests: request without header succeeds; repeated requests return the same user;
  user is created on first request; default (flag off) still returns 401 without a
  token.

## Client (`app/`)

- Delete `lib/auth/` entirely (controller, repository, models, token storage, login and
  register screens), `AuthGate`, the `/register` route, the `DEV_AUTO_LOGIN` flag
  (`config.dart`, CI workflow).
- `MaterialApp.home` is `HomeShell` directly.
- Remove the `token` parameter and `Authorization` header from `api_client`,
  waypoints/tracks/mediafile repositories; controllers stop reading a token.
  `apiClientProvider` moves to a non-auth location.
- `SettingsScreen`: remove the logout tile; leave an empty screen with the existing
  app bar title.
- Tests: delete login/register/token-storage/auth-controller tests; update the rest
  (`app_test`, `home_shell_test`, repository/controller tests) for the removed token.

## Risks

- With `AUTH_DISABLED=true` anyone reaching port 8500 acts as the single user; the port
  must only be reachable inside the VPN.
- A new client build works only against a backend running in this mode.
- Installing the CI-built APK still requires uninstall (signature mismatch), which
  wipes local-only data such as per-waypoint icon assignments.
