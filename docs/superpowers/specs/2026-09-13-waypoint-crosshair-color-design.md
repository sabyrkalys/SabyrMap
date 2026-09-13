# Waypoint crosshair creation + custom color — design spec

Date: 2026-09-13

## Context

This is Slice B from the post-device-testing feedback recorded after Slice A
(GPS my-location/autocenter/5m interval) shipped. Two changes, bundled
because both touch the waypoint creation/edit flow:

1. Replace long-press-on-map waypoint creation with a persistent crosshair
   reticle at the map's center plus a dedicated button that creates the
   waypoint at the crosshair's current coordinate. The button **fully
   replaces** long-press — they do not coexist.
2. Let the user pick a custom color for a waypoint (full HSV/any-hue picker)
   as an override on top of the existing type-based default color.

Both are classified **architectural**: (1) is a UX overhaul across the map
screen's core interaction model, (2) requires a new backend field, a
migration, and changes through the full stack (model → schema → router →
repository → form → map rendering).

Per the now-resolved "two release tracks" constraint, this must be built
from scratch — no code or design copied from the AlpineQuest APK or its
`flutter_ui/` reference folder, beyond the already-approved
`zoom_controls.dart`/`create_marker_fab.dart` generic style reference.

## Goals

- Waypoint creation happens via crosshair + button, not long-press.
- A waypoint can have an optional custom color, independent of its type.
- Existing waypoints without a custom color keep rendering with their
  type's default color (`waypointTypeColors`), unchanged.

## Non-goals

- No change to waypoint types, icons, or the set of available types.
- No change to track rendering/measurement (already shipped).
- No live camera-position UI beyond what's needed to read the crosshair's
  coordinate (no coordinate readout, no manual entry).

## Design

### 1. Backend: nullable `color` field

- `Waypoint` model (`api/app/models/waypoint.py`) gains
  `color: Mapped[str | None] = mapped_column(String(7), nullable=True)`.
- New Alembic migration adding this column (nullable, no server default —
  `null` means "use the type default").
- `WaypointCreateRequest`/`WaypointUpdateRequest`
  (`api/app/schemas/waypoints.py`) gain an optional `color: str | None`
  field, validated with a strict hex pattern: `^#[0-9A-Fa-f]{6}$`. A
  Pydantic field validator rejects anything else with a 422, matching how
  other fields are already validated.
- `WaypointResponse` gains `color: str | None`.
- `create_waypoint()` (`api/app/services/resources.py`) gains a `color:
  str | None = None` parameter, passed straight into `Waypoint(...)`.
- `update_waypoint` router logic: same pattern as `note` — if
  `payload.color is not None`, assign it; but unlike `note`, an explicit
  empty/absent value must be distinguishable from "clear the override".
  Since the field is `str | None` and always hex-validated when present,
  the router treats `payload.color is not None` as "set/replace" and
  provides no separate "clear" signal in this PATCH shape — clearing means
  sending `color: null` explicitly, which Pydantic's `is not None` check
  as currently modeled would *not* apply. To support explicit clearing,
  `WaypointUpdateRequest.color` uses a sentinel-free "field present"
  check: the router reads `"color" in payload.model_fields_set` (Pydantic
  v2) rather than `is not None`, so:
  - field omitted entirely → leave unchanged
  - field sent as `null` → clear the override (`entity.color = None`)
  - field sent as a hex string → set the override

### 2. Frontend model + rendering

- `Waypoint` (`app/lib/waypoints/waypoint_models.dart`) gains a nullable
  `color` field, parsed from `json['color'] as String?`.
- `circleOptionsForWaypoint` (`app/lib/map/map_screen.dart`) resolves
  color as: `waypoint.color ?? waypointTypeColors[waypoint.type] ??
  waypointTypeColors[defaultWaypointType]!`. The circle's cache key (used
  to skip redundant `updateCircle` calls) changes from `'${type}|$isOwn'`
  to `'${type}|$isOwn|${color ?? ''}'` so a color-only edit still triggers
  a re-render.
- `WaypointsRepository.create`/`update` (`app/lib/waypoints/
  waypoints_repository.dart`) gain a `color` parameter and include it in
  the request body (`null` sent as JSON `null` on update to support
  clearing; omitted — not sent at all — on create when no color was
  picked, since create has no "existing value" to clear).

### 3. Map screen: crosshair + create button

- Remove `onMapLongClick` wiring for waypoint creation. The
  `MapLibreMap.onMapLongClick` callback is dropped entirely (nothing else
  uses it).
- `trackCameraPosition: true` is added to the `MapLibreMap` widget so
  `controller.cameraPosition` stays live as the user pans/zooms (verified
  against `maplibre_gl` 0.26.2's controller: `onCameraMove`/`onCameraIdle`
  update `_cameraPosition` only when this flag is set).
- A persistent, non-interactive crosshair overlay (a centered `Icon`,
  `IgnorePointer`-wrapped) is layered over the map via `Stack`, positioned
  with `Alignment.center` regardless of screen size.
- A `FloatingActionButton` (key `create_waypoint_button`) is added to the
  `Scaffold`. On press: read `_controller!.cameraPosition!.target`
  (falling back to a no-op with a snackbar if the controller or camera
  position isn't available yet), open the existing `WaypointFormSheet`
  flow, and on a non-null result call `createWaypoint(...)` with the
  crosshair's lat/lng — the same call site logic that `_onMapLongClick`
  used, just fed a different coordinate source. `_onMapLongClick` is
  deleted.

### 4. Waypoint form: inline color override

- `WaypointFormSheet` (`app/lib/waypoints/waypoint_form_sheet.dart`) adds
  local state `String? _selectedColor`, initialized from
  `widget.existing?.color`.
- Below the type chips, a swatch button (key `waypoint_color_swatch`)
  renders a filled circle in the *effective* color — `_selectedColor ??
  waypointTypeColors[_selectedType]!` — recomputed on type change so the
  swatch reflects a live default when no override is set (confirmed:
  changing type never clears an existing override, only affects what the
  swatch shows as a fallback).
- Tapping the swatch opens a `showDialog` wrapping `flutter_colorpicker`'s
  `ColorPicker` (HSV wheel + hex input), pre-seeded with the effective
  color computed the same way. The dialog has "Select" (sets
  `_selectedColor` to the picked hex) and "Reset to default" (sets
  `_selectedColor = null`) actions, plus a plain "Cancel".
- `WaypointFormResult` gains `final String? color;`. `showWaypointFormSheet`
  and both call sites in `map_screen.dart` (`_onMapLongClick`'s
  replacement, `_editWaypoint`) pass `result.color` through to
  `createWaypoint`/`updateWaypoint`.
- New dependency: `flutter_colorpicker` (pub.dev, MIT license) added to
  `app/pubspec.yaml`.

## Data flow summary

```
FAB press → cameraPosition.target (lat/lng)
          → showWaypointFormSheet (name, type, note, color)
          → WaypointsController.createWaypoint(..., color)
          → HttpWaypointsRepository.create (POST /waypoints, color: hex|omitted)
          → WaypointCreateRequest (hex-validated) → create_waypoint() → Waypoint row
          → WaypointResponse (color) → Waypoint.fromJson → circleOptionsForWaypoint
```

## Testing

- Backend: hex validator accepts/rejects cases; `create_waypoint`/PATCH
  round-trip color set/clear/omit via the "field present" check; existing
  waypoint tests updated for the new field. Verified against a real
  Postgres/PostGIS DB (migration + pytest), per the lesson in
  [[project_migration_test_gap]] — don't trust `metadata.create_all` alone.
- Frontend: `circleOptionsForWaypoint` unit tests for color precedence
  (override present / absent); `WaypointFormSheet` widget tests for swatch
  default, picker round-trip, reset-to-default, and type-change-preserves-
  color; `MapScreen` widget tests for FAB triggering `createWaypoint` with
  the crosshair's coordinate instead of a long-press coordinate, and for
  `onMapLongClick` no longer being wired.
- `flutter analyze` clean, full `flutter test` suite green, backend
  `pytest` green against real DB.

## Open items for the implementation plan

- Exact Alembic migration revision id/message (generated at implementation
  time, following the existing migration chain from `7d7472006ec0`).
- Precise crosshair icon/size and FAB icon — cosmetic, decided during
  implementation, not blocking design approval.
