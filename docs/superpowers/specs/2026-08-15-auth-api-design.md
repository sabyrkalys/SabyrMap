# Authentication API (Register / Login) — Design

Date: 2026-08-15
Status: Approved, pending implementation plan

## Context

AlpineQuest currently exposes only `GET /health`. The data model and service
layer for organizations, users, and roles already exist
([Roles and Resource Sharing design](2026-08-12-roles-and-sharing-design.md)),
including `create_personal_organization_and_owner`. There is no way for an
external client (web/mobile) to actually create an account or authenticate —
every user and resource in the database so far was inserted by calling
service functions directly from a Python shell.

This spec defines the first real API surface: registration, login, and an
identity-check endpoint, plus the JWT-based auth mechanism every future
protected endpoint will build on.

Dependencies already declared in `requirements.txt` and used as-is:
`PyJWT` (token issuing/verification), `bcrypt` (password hashing),
`python-multipart` (form parsing, unused here but already present),
`httpx` (test client transport).

`app/config.py` already has `JWT_SECRET_KEY` and
`ACCESS_TOKEN_EXPIRE_MINUTES` (1440 = 24h) — reused unchanged.

## Decisions

### 1. Token delivery: JWT in the JSON response body (Bearer)

`POST /auth/register` and `POST /auth/login` return
`{"access_token": "...", "token_type": "bearer"}` in the response body. The
client is responsible for storing it and sending
`Authorization: Bearer <token>` on subsequent requests. No cookies, no
CSRF handling — this suits an API consumed by a mobile app and/or a
separate-origin web frontend, and avoids cookie/CORS complexity for what is
currently an API-only backend with no server-rendered frontend.

### 2. Registration always creates a personal organization

`POST /auth/register` takes `{email, password}` and always provisions a new
personal organization with the caller as its `owner`, via the existing
`create_personal_organization_and_owner`. There is no "join an existing
organization" path yet — invites/org-joining is a separate, deliberately
deferred feature (see Out of scope).

### 3. JWT payload and verification

Payload: `{"sub": "<user.id as str>", "exp": <unix timestamp>}`. `sub` is the
only identity claim — role/org_id are not embedded in the token, they are
looked up fresh from the database on every request via `get_current_user`.
This means a role change or soft-delete takes effect on the user's very next
request, instead of staying valid until the old token expires.

Verification (`get_current_user` FastAPI dependency):
1. Extract `Authorization: Bearer <token>` header; missing/malformed → 401.
2. `jwt.decode` with `JWT_SECRET_KEY`, algorithm `HS256`; invalid signature or
   expired → 401.
3. Look up `User` by `sub` where `deleted_at IS NULL`; not found → 401.
4. Return the `User` object for the route to use.

All three failure modes return the same generic 401 body
(`{"detail": "Could not validate credentials"}`) — no distinction between
"expired" and "malformed" is exposed to the client, to avoid giving probing
clients extra signal.

### 4. Password hashing

`bcrypt.hashpw` / `bcrypt.checkpw` directly (no passlib wrapper — one
extra dependency for no behavior we need). Cost factor uses bcrypt's default
(12 rounds via `bcrypt.gensalt()`).

### 5. Login failure is a single generic error

`POST /auth/login` takes `{email, password}`. Whether the email doesn't
exist, is soft-deleted, or the password is wrong, the response is always
`401 {"detail": "Invalid email or password"}`. This prevents user
enumeration via the login endpoint. Lookup filters `deleted_at IS NULL`, so a
soft-deleted user's old credentials simply stop working — indistinguishable
from a wrong password.

### 6. Duplicate email at registration is a distinct error

Unlike login, registration *does* reveal whether an email is taken:
`POST /auth/register` with an email already used by an active
(`deleted_at IS NULL`) user returns `409 {"detail": "Email already
registered"}`. This is standard for signup flows (the user needs to know to
go log in instead) and doesn't leak anything beyond "an account with this
address exists," which the user themselves supplied.

### 7. `GET /auth/me`

Returns the current authenticated user's own profile:
`{"id", "email", "role", "org_id"}`. Requires a valid token via
`get_current_user`. This is the first protected endpoint, serving as the
end-to-end smoke test for the whole auth flow, and the pattern every future
protected route (waypoints, tracks, sharing) will copy.

## Request/response shapes

```
POST /auth/register
  in:  { "email": str, "password": str }
  200: { "access_token": str, "token_type": "bearer" }
  409: { "detail": "Email already registered" }
  422: (pydantic validation — malformed email, empty password, etc.)

POST /auth/login
  in:  { "email": str, "password": str }
  200: { "access_token": str, "token_type": "bearer" }
  401: { "detail": "Invalid email or password" }
  422: (pydantic validation)

GET /auth/me
  header: Authorization: Bearer <token>
  200: { "id": uuid, "email": str, "role": str, "org_id": uuid }
  401: { "detail": "Could not validate credentials" }
```

## Components

- `app/schemas/auth.py` — Pydantic request/response models:
  `RegisterRequest`, `LoginRequest`, `TokenResponse`, `UserResponse`.
- `app/services/auth.py` — framework-agnostic logic, testable without HTTP:
  - `hash_password(password: str) -> str`
  - `verify_password(password: str, password_hash: str) -> bool`
  - `create_access_token(user_id: UUID) -> str`
  - `decode_access_token(token: str) -> UUID` (raises on invalid/expired)
- `app/dependencies.py` — `get_current_user(token, db) -> User` FastAPI
  dependency, built on `decode_access_token` + a DB lookup.
- `app/routers/auth.py` — the three endpoints, wired to `services/auth.py`,
  `services/organizations.py` (registration), and `dependencies.py` (the
  `/me` route).
- `app/main.py` — `app.include_router(auth_router)`.

## Data flow

**Register:** request → Pydantic validation → check no active user has this
email → `bcrypt.hashpw` → `create_personal_organization_and_owner` (existing
service, single DB transaction) → `create_access_token` → 200 with token.

**Login:** request → look up active user by email → `bcrypt.checkpw`
(constant-time compare built into bcrypt) → on success,
`create_access_token` → 200 with token; any failure → 401.

**Authenticated request (`/me` and every future protected route):**
`Authorization` header → `get_current_user` dependency resolves it to a
`User` row → route handler runs with a trusted, live-from-DB user object.

## Error handling

| Condition | Response |
|---|---|
| Register: email already active | 409 |
| Register: invalid email format / empty password | 422 (Pydantic) |
| Login: no such active user, or wrong password | 401 (generic) |
| Missing/malformed/expired/invalid-signature token | 401 (generic) |
| Token valid but user soft-deleted since issuance | 401 (generic — same as "not found") |

## Testing approach

- `app/services/auth.py` unit tests: hash/verify round-trip, wrong password
  rejected, token round-trip (`create_access_token` → `decode_access_token`),
  expired token rejected, tampered token rejected.
- `tests/test_auth_api.py`, using the existing `client` fixture
  (`TestClient` + `get_db` override, from `tests/conftest.py`):
  - register → 200 + token; `/me` with that token → correct user/org/role.
  - register twice with same email → second call 409.
  - login with correct credentials → 200 + token.
  - login with wrong password / unknown email → 401, same body either way.
  - `/me` with no header → 401; with garbage token → 401.
  - soft-deleted user (set `deleted_at`, bypassing the API) can no longer
    log in or use their old token.

## Out of scope (deliberately deferred)

- Joining an existing organization via invite/code at registration.
- Refresh tokens / token revocation / logout endpoint (24h expiry is the
  only lifecycle control for now).
- Password reset / email verification.
- Rate limiting on login/register (relevant before production, not for this
  first pass).
- Authorization checks beyond "is this a valid, non-deleted user" — role-
  and share-based access control (`can_view_resource`, already implemented)
  gets wired into routes when the resource endpoints are built next.
