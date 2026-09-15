# Waypoint custom icons — design spec

Date: 2026-09-15

## Context

Next unclaimed item from the original roadmap's Phase 3 ("метки с иконками").
Today a waypoint's on-map appearance is a solid-color `Circle`
(`circleOptionsForWaypoint` in `app/lib/map/map_screen.dart`) whose color
comes from `waypoint.color` or `waypointTypeColors[waypoint.type]` — there
is no image/shape distinction between types, only color. This spec adds
real image icons, sourced from files the user drops into a device folder
outside the app (no in-app upload/gallery/camera UI, no backend changes).

Classified **architectural**: new local file-scanning subsystem, a
Circle→Symbol rendering path on the map, and per-format (SVG vs
PNG/JPEG) color-handling rules.

## Goals

- A waypoint can show a real image as its map marker instead of a colored
  circle, picked from files the user places in a folder on the device.
- SVG icons can be tinted to the waypoint's color (existing HSV picker);
  PNG/JPEG icons render as-is, with color selection unavailable for them.
- The icon choice is per-device, per-waypoint: not synced to the backend,
  not visible to other users viewing a shared waypoint (they see the
  existing colored-circle fallback).
- Waypoints that never had an icon picked keep behaving exactly as today.

## Non-goals

- No in-app file upload, camera capture, or gallery picker.
- No backend/schema changes, no icon sync between devices or users.
- No icon library management screen (rename/delete happens only via the
  OS file manager, outside the app).
- No change to track rendering or the crosshair/color feature already
  shipped.

## Design

### 1. Icon source folder

- Path: `<app external files dir>/mediafile/iconTypes/` — i.e.
  `path_provider`'s `getExternalStorageDirectory()` +
  `/mediafile/iconTypes`. On Android this resolves to
  `/storage/emulated/0/Android/data/<applicationId>/files/mediafile/iconTypes`,
  visible in any file manager without extra runtime permissions, and
  cleaned up automatically on app uninstall.
- A new `IconLibraryScanner` (`app/lib/icons/icon_library_scanner.dart`)
  creates the folder if missing (`Directory(...).create(recursive: true)`)
  and exposes `Future<List<IconFile>> scan()`, returning entries for every
  file with extension `.png`, `.jpg`, `.jpeg`, or `.svg` (case-insensitive),
  sorted by filename. `IconFile` is `{String path, String fileName,
  String displayName, IconFileFormat format}` — `displayName` is the
  filename without its extension; `IconFileFormat` is an enum
  `{svg, raster}` (`.svg` → `svg`, everything else → `raster`).
- The scanner takes an injectable `FileSystem` (`package:file`) so tests
  use `MemoryFileSystem` instead of touching real device storage.
- New dependency: `path_provider` (already a transitive need, added
  explicitly), `file` (for the testable filesystem seam).

### 2. Local-only persistence of the icon choice

- New `WaypointIconStore` (`app/lib/icons/waypoint_icon_store.dart`)
  wraps a `SharedPreferences`-backed (or a small JSON file under the
  app's documents dir — implementation detail, either works) map of
  `waypointId → fileName`. Two methods: `String? iconFor(String
  waypointId)`, `Future<void> setIcon(String waypointId, String?
  fileName)` (`null` clears — "use default circle").
- This store is never sent to the backend and never read from it. A
  waypoint fetched from the API (own or shared) is looked up in this
  local store by id; a miss (including on another user's device, or a
  fresh install) means "no icon — render the existing colored circle".
- New dependency: `shared_preferences` (if not already present — not in
  current `pubspec.yaml`, so added).

### 3. Map rendering: Circle vs. Symbol per waypoint

- `map_screen.dart` gains a `SymbolManager` alongside the existing
  `CircleManager`/`LineManager` (same lifecycle: created in
  `_onStyleLoaded`, disposed on style reload, same stale-manager
  reconciliation pattern already used for circles/lines).
- `_syncCircles`/a new `_syncSymbols` partition the current waypoint list
  by `WaypointIconStore.iconFor(waypoint.id) != null`: waypoints with a
  stored icon go through `_syncSymbols` (as `Symbol`s), the rest keep
  going through the existing `_syncCircles` path unchanged. A waypoint
  moving between the two states (icon picked/cleared) is handled by
  removing it from one manager and adding it to the other — same
  remove/add bookkeeping already used for stale circles.
- `IconImageCache` (`app/lib/icons/icon_image_cache.dart`) resolves an
  `(fileName, colorHex)` pair to a registered MapLibre image name,
  calling `controller.addImage(name, bytes)` at most once per pair
  (cached in a `Map<String, bool>` of already-registered names, cleared
  on style reload alongside the other per-style caches):
  - **raster** (`png`/`jpg`/`jpeg`): read the file's bytes directly,
    `addImage('icon_raster_$fileName', bytes)`. No tinting; the color
    picker is irrelevant for this waypoint.
  - **svg**: rasterize via `flutter_svg`'s `vg.loadPicture` into a
    `ui.PictureRecorder`/`Canvas`, painting through a `ColorFilter.mode(
    tintColor, BlendMode.srcIn)` so the whole glyph takes the waypoint's
    effective color (`waypoint.color ?? waypointTypeColors[type]`),
    then `picture.toImage(w, h)` → `image.toByteData(format:
    ui.ImageByteFormat.png)` → `addImage('icon_svg_${fileName}_$colorHex',
    bytes)`. Re-tinting on a color change registers a new image name
    (old ones are left registered for the style's lifetime — cheap,
    bounded by how many distinct colors get picked in one session).
  - `SymbolOptions.iconImage` is set to the resolved name;
    `SymbolOptions.iconSize` fixed (same visual footprint as the current
    circle radius, decided cosmetically during implementation).
- New dependency: `flutter_svg`.

### 4. Waypoint form: icon picker

- `WaypointFormSheet` gains a new row below the existing color swatch:
  an "Иконка" button showing the current pick's thumbnail (or a
  placeholder meaning "default circle").
- Tapping it opens a bottom sheet (`showModalBottomSheet`) built by a
  new `IconPickerSheet` (`app/lib/icons/icon_picker_sheet.dart`):
  calls `IconLibraryScanner.scan()` fresh every time it opens (per the
  approved always-rescan behavior), renders results in a `GridView` of
  thumbnails + filename-minus-extension labels, plus a leading
  "Стандартная" tile that clears the pick. Selecting a tile pops the
  sheet with the chosen `IconFile?` (`null` = "Стандартная").
- `WaypointFormResult` gains `final String? iconFileName;` — populated
  from the picker, independent of the existing `color` field.
- When the picked icon's format is `raster`, the form hides/disables the
  existing color swatch row (color has no effect); switching back to
  "Стандартная" or to an `svg` icon re-enables it. The swatch's
  `_effectiveColorHex` logic is unchanged.
- `showWaypointFormSheet` call sites (`map_screen.dart`'s create-button
  flow and edit flow) don't call any repository method for the icon —
  after the existing `createWaypoint`/`updateWaypoint` call returns
  (which only persists name/type/note/color to the backend as today),
  the caller calls `WaypointIconStore.setIcon(waypoint.id,
  result.iconFileName)` to persist the local-only pick. For a brand-new
  waypoint this means the icon is stored keyed by the id the backend
  just assigned, right after creation succeeds.

## Data flow summary

```
IconPickerSheet.scan() → mediafile/iconTypes/*.{png,jpg,jpeg,svg}
                       → user picks one (or "Стандартная")
WaypointFormResult.iconFileName → (after create/update API call succeeds)
                                 → WaypointIconStore.setIcon(waypointId, fileName)

Map render, per waypoint:
  WaypointIconStore.iconFor(id) == null → existing Circle path (unchanged)
  WaypointIconStore.iconFor(id) == fileName →
    IconImageCache.resolve(fileName, effectiveColorHex) → addImage (cached)
    → Symbol with iconImage: resolved name
```

## Testing

- `IconLibraryScanner`: unit tests against `MemoryFileSystem` — empty
  folder, mixed extensions (unsupported ones ignored), sort order,
  folder auto-created when missing.
- `WaypointIconStore`: unit tests for set/get/clear round-trip, and "no
  entry" returning `null`.
- `IconImageCache`: unit test that a raster file's bytes are passed to
  `addImage` unchanged, and that an SVG's rasterized output actually
  contains the requested tint color (sample a pixel), plus a cache-hit
  test (second resolve for the same pair doesn't call `addImage` again).
- `map_screen.dart`: extend the existing circle-sync tests with cases
  proving a waypoint with a stored icon goes through the symbol path and
  not the circle path, and that toggling the icon (set → clear) moves it
  between managers.
- `WaypointFormSheet` widget tests: picker round-trip sets
  `iconFileName`; picking a raster icon hides the color swatch; picking
  an svg icon (or "Стандартная") shows it; "Стандартная" clears the pick.
- `flutter analyze` clean, full `flutter test` suite green. No backend
  tests affected (no backend changes).

## Open items for the implementation plan

- Exact thumbnail size/grid column count in `IconPickerSheet` —
  cosmetic, decided during implementation.
- Whether `WaypointIconStore` backs onto `shared_preferences` or a flat
  JSON file under the app's documents directory — either satisfies the
  local-only, per-device requirement; picked during implementation based
  on which is less code given what's already a dependency.
- Fixed `iconSize`/anchor for `SymbolOptions` to visually match the
  current circle's footprint — decided during implementation, not
  blocking design approval.
