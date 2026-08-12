# Roles and Resource Sharing — Design

Date: 2026-08-12
Status: Approved, pending implementation plan

## Context

AlpineQuest is a multi-tenant offline-map SaaS (waypoints, tracks, sharing, plugins).
`User` currently has a flat `role: str` column with no formal constraint, and there
is no ownership or sharing model for map resources. This spec defines:

1. The organization membership model, including solo/personal use.
2. The fixed set of organization roles.
3. How waypoints/tracks are owned and how visibility is determined by default.
4. How resource-level sharing works (to a specific user or to the whole org).
5. Soft delete across `organizations`, `users`, and resources.

## Decisions

### 1. Every user belongs to exactly one organization

`users.org_id` stays `NOT NULL`. There is no "orgless" user state. A person who
wants to use the app individually (not as part of a team) gets a **personal
organization** auto-created at signup (`plan='personal'`), and becomes its sole
`owner`. This avoids branching every authorization check on "does this user have
an org or not" — a solo user is simply an organization of one.

### 2. Fixed roles (no custom/dynamic roles)

Roles are a closed set, stored as a Postgres ENUM (`Role`) on `users.role`:

- `owner` — created the org, manages billing/plan, full control, can delete org
- `admin` — manages members, sees all resources in the org (oversight), cannot manage billing
- `member` — creates/edits their own resources
- `viewer` — read-only

No dynamic `roles`/`permissions` tables — the org doesn't let tenants define
custom roles, so a full RBAC schema would be unused complexity.

### 3. Resource ownership and default visibility

Waypoints and tracks are **private to their creator by default**. Other org
members do NOT see them automatically, except:

- `owner` and `admin` always see all resources in their organization (oversight —
  e.g. a team laying geodetic markers needs a lead who sees the whole set).
- A resource becomes visible to others only via explicit sharing (below).

### 4. Resource modeling: shared base table (chosen over 3 alternatives)

Four options were compared for how resources and their shares are stored:

| Option | FK integrity | Duplication | Cross-type query |
|---|---|---|---|
| A. Polymorphic `resource_shares` (`resource_type`+`resource_id`, no real FK) | No | None | Needs per-type query |
| B. Per-type share table (`waypoint_shares`, `track_shares`, ...) | Yes | Schema/logic duplicated per resource type | UNION across tables |
| **C. Base `resources` table + single `resource_shares` (chosen)** | Yes | None | Single JOIN |
| D. `shared_with` JSONB column on each resource | No | Logic duplicated per resource type | Table scan, no index |

**Chosen: C.** `resources` holds the fields common to every shareable entity
(`org_id`, `owner_id`, `resource_type`, timestamps). `waypoints` and `tracks`
hold only their type-specific fields, keyed on the *same* `id` as their
`resources` row (shared primary key). `resource_shares` has a real foreign key
to `resources.id`, so cascades and integrity are enforced by Postgres, and a
single shares table serves every current and future resource type without
duplicating schema or authorization logic.

Creating a resource is a single transaction: insert into `resources`, then
insert into the type table using the same generated id.

### 5. Sharing model

`resource_shares`:
- `resource_id` → `resources.id` (FK, `ON DELETE CASCADE`)
- `shared_with_user_id` → `users.id` (FK, `ON DELETE CASCADE`, nullable)
- `scope`: ENUM `user` | `organization`
  - `user`: shared with one specific person (`shared_with_user_id` required)
  - `organization`: shared with everyone in the resource's org (`shared_with_user_id` must be null)
- `permission`: ENUM `view` | `edit`
- `created_by` → `users.id`, `created_at`

CHECK constraint enforces `scope='user' ⇒ shared_with_user_id NOT NULL` and
`scope='organization' ⇒ shared_with_user_id IS NULL`.

Unique constraint on `(resource_id, shared_with_user_id)` prevents duplicate
shares to the same person for the same resource.

### 6. Visibility rule (application logic, not a table)

A resource is visible to a user if, and only if, the resource is not soft-deleted, and:

- the user is the owner (`resources.owner_id = user.id`), OR
- the user's role in the resource's org is `owner` or `admin`, OR
- a `resource_shares` row exists with `scope='organization'` for that org, OR
- a `resource_shares` row exists with `scope='user'` and `shared_with_user_id = user.id`

### 7. Soft delete

`deleted_at: timestamptz NULL` is added to `organizations`, `users`, and
`resources` (inherited implicitly by `waypoints`/`tracks` via shared id).
Deletion sets `deleted_at` instead of removing the row. All reads filter
`deleted_at IS NULL`.

Consequence: `users.email` can no longer use a plain global `UNIQUE`
constraint, since a soft-deleted user's email must become available again.
It becomes a partial unique index: `UNIQUE (email) WHERE deleted_at IS NULL`.

`resource_shares` rows are not soft-deleted — revoking a share is a hard
delete of that row (shares carry no history requirement).

## Schema summary

```
organizations
  id, name, plan, limits_json, created_at, deleted_at

users
  id, org_id (FK), email (partial unique, deleted_at IS NULL),
  password_hash, role (ENUM), created_at, deleted_at
  index: ix_users_org_id

resources
  id, org_id (FK), owner_id (FK -> users.id), resource_type (ENUM),
  created_at, deleted_at
  indexes: ix_resources_org_id, ix_resources_owner_id,
           ix_resources_org_type (org_id, resource_type)

waypoints
  id (PK, FK -> resources.id), name, geom (GIST index)

tracks
  id (PK, FK -> resources.id), name, geom (GIST index)

resource_shares
  id, resource_id (FK -> resources.id, CASCADE),
  shared_with_user_id (FK -> users.id, CASCADE, nullable),
  scope (ENUM: user|organization), permission (ENUM: view|edit),
  created_by (FK -> users.id), created_at
  indexes: ix_resource_shares_resource_id, ix_resource_shares_user_id
  unique: (resource_id, shared_with_user_id)
  check: scope/shared_with_user_id consistency
```

## Out of scope (deliberately deferred)

- Custom/dynamic roles or granular per-action permissions beyond the 4 fixed roles.
- Sharing via public link or with users outside the organization (guest access).
- Plugin resource types — the `resources` base table is designed to support
  them later without schema changes to `resource_shares`.

## Testing approach

- Model-level tests: constraint enforcement (role enum, scope/user check,
  unique share, partial unique email), soft-delete filtering.
- Authorization-rule tests: one test per branch of the visibility rule
  (owner, admin/owner-in-org, org-scope share, user-scope share, no access).
- Migration tests: `alembic upgrade head` / `downgrade` round-trip on a fresh
  test database (already covered by existing `conftest.py` fixture pattern).
