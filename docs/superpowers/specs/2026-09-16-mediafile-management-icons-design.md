# mediafile file management (core) + custom-types entry point — design spec

Date: 2026-09-16

## Context

This is the first sub-project of a larger, deliberately-decomposed initiative: an
in-app file-management layer for the `mediafile` folder that already backs
custom waypoint icons (see `docs/superpowers/specs/2026-09-15-waypoint-custom-icons-design.md`).
The full initiative (from a reference prototype the user shared) envisions a
`/mediafile` root with several subfolders — `maps/` (offline `.mbtiles`),
`waypoints/` and `tracks/` (GPX/KMZ/KML/CSV/GeoJSON/AQZ export), `photos/`,
and `custom-types/` (marker icon files) — each reachable from the relevant
tab, with app-level import (via a system file picker) and, for the data
subfolders, multi-format export. That whole initiative is too large for one
spec; per the decomposition agreed with the user, it is split into:

1. **This spec**: the reusable "browse one mediafile subfolder" screen (list,
   import, delete) plus its first real wiring — the `custom-types` folder
   (marker icons), reachable from the "Метки" tab.
2. (Later, separate specs) `maps/`, `waypoints/`/`tracks/` format export,
   `photos/`.

**Why this matters now:** the custom-icons feature (shipped 2026-09-15) reads
icon files from `mediafile/iconTypes/` on the device, but nothing in the app
puts files there — the user must reach the folder via the OS file manager.
On the test device this turned out to work (Android's Files app can browse
`Android/data/<package>/files/...` there), but a normal user has no obvious
reason to know that folder exists or where to find it. An in-app screen that
lists what's there and lets the user import a file via the standard Android
file picker removes that friction entirely and matches the product direction
the reference prototype lays out.

## Goals

- A generic, reusable screen shows the files in one named `mediafile`
  subfolder: name, size, an "Импорт" action (opens the system file picker,
  copies the chosen file in), and a per-file delete action (with
  confirmation).
- The existing icon folder `mediafile/iconTypes` is renamed to
  `mediafile/custom-types` — path only; the file formats it holds
  (`.png`/`.jpg`/`.jpeg`/`.svg`) and everything that reads them (the icon
  picker's `IconLibraryScanner`, `icon_picker_sheet.dart`, the waypoint form)
  are unaffected beyond the path change.
- This screen is reachable from the "Метки" tab (the existing waypoints list
  screen) via a new AppBar action, labeled "Файлы меток", scoped to
  `custom-types`.

## Non-goals

- No export (share/save-out) of any kind in this sub-project — export in
  GPX/KMZ/KML/CSV/GeoJSON/AQZ applies to waypoint/track *data*, not to icon
  files, and is a separate, later sub-project (waypoints/tracks export).
- No `maps/`, `waypoints/`, `tracks/`, or `photos/` subfolder screens yet —
  those are later sub-projects, each reusing the screen this spec builds.
- No change to how the icon picker (`icon_picker_sheet.dart`) itself works —
  it keeps scanning whatever folder path it's given; only the path constant
  changes.
- No reading of the OS "Downloads" folder listing directly (a variant seen in
  the reference prototype) — import goes through Android's standard system
  file picker (Storage Access Framework), which can browse anywhere on the
  device, not just Downloads. This was an explicit choice over copying the
  prototype's Downloads-only browsing screen.

## Design

### 1. Dependency: `file_picker`

Add `file_picker: ^11.0.3` to `app/pubspec.yaml`. Verified directly against
the installed package source (`FilePicker.pickFiles(...)` in
`file_picker-11.0.3/lib/src/file_picker.dart`):

```dart
static Future<FilePickerResult?> pickFiles({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  // ...other params not used here
});
```

`FilePickerResult.files` is `List<PlatformFile>`; `PlatformFile.path` is
`String?` (non-null on Android, which is this app's only real target),
`.name` is the filename with extension, `.size` is bytes. The package ships
its own Android manifest fragment (a `<queries>` block for
`ACTION_GET_CONTENT`); no additional permission or manifest entry is needed
in the app — it uses Android's Storage Access Framework, not raw storage
permissions.

Selecting extensions: `FileType.custom` with an explicit
`allowedExtensions` list (e.g. `['png', 'jpg', 'jpeg', 'svg']`) — not
`FileType.image`, since that maps to Android's `image/*` MIME bucket and
SVG's registration there is inconsistent across devices/file managers;
`FileType.custom` with explicit extensions is unambiguous.

### 2. Generic subfolder-browsing service and screen

- `app/lib/mediafile/mediafile_folder_service.dart` — a small,
  format-agnostic service (not tied to icons) that operates on a given
  subfolder name under the resolved `mediafile` root (reusing the same
  root-resolution logic already proven in
  `app/lib/icons/icon_library_scanner.dart`'s
  `IconLibraryScanner.resolveBaseDirectory()` — external-storage-first, app
  documents directory fallback):
  - `class MediaFileEntry { final String path; final String fileName; final int sizeBytes; }`
  - `class MediaFileFolderService { MediaFileFolderService({required String subfolder, FileSystem? fileSystem}); Future<List<MediaFileEntry>> list(); Future<void> importFile(String sourcePath); Future<void> delete(String fileName); }`
  - `importFile` copies the given source path's bytes into the subfolder
    under its own basename (via `dart:io`'s `File.copy`-equivalent —
    `File(sourcePath).readAsBytes()` then write, mirroring the pattern
    already used in this codebase's icon renderer for raw file reads, so
    the same test-friendly `FileSystem` seam applies); if a file with that
    name already exists, it's overwritten (last import wins — no
    silent-rename-on-conflict logic, since that's unnecessary complexity
    for a single-user local folder).
  - `delete` removes the named file; a missing file is treated as success
    (idempotent — matches how `WaypointIconStore.setIcon(id, null)` already
    tolerates "nothing to remove").
- `app/lib/mediafile/mediafile_folder_screen.dart` — the reusable UI:
  `class MediaFileFolderScreen extends StatefulWidget { const
  MediaFileFolderScreen({required this.title, required this.subfolder,
  required this.allowedExtensions, MediaFileFolderService? service}); }`
  (the optional `service` param is the test seam, mirroring
  `IconPickerSheet`'s optional `scanner` param). On build it lists entries
  (rescanned on push and after every import/delete — no caching, matching
  the icon picker's "always rescan" precedent), renders a
  `ListView` of `(fileName, size)` rows each with a trailing delete
  `IconButton`, an empty state ("Здесь пока нет файлов" — exact wording
  decided during implementation, non-blocking) when the list is empty, and
  a `FloatingActionButton`/AppBar action labeled "Импорт" that calls
  `FilePicker.pickFiles(type: FileType.custom, allowedExtensions:
  widget.allowedExtensions)`, and on a non-null, non-empty result calls
  `service.importFile(result.files.single.path!)` then re-lists. Delete
  taps open a `showDialog` confirmation ("Удалить файл «name»?" / Отмена /
  Удалить) before calling `service.delete(fileName)`.

### 3. Rename `iconTypes` → `custom-types`

- In `app/lib/icons/icon_library_scanner.dart`,
  `IconLibraryScanner`'s folder-suffix constant changes from
  `'mediafile/iconTypes'` to `'mediafile/custom-types'`. Nothing else in
  that file changes — `IconFile`, `iconFileFormatForPath`, `scan()`'s
  logic, and the `baseDirectoryPath` test-injection seam are all
  path-format-agnostic already.
- No data migration needed: this folder holds user-supplied icon files the
  user places manually (or, after this sub-project ships, imports via the
  new screen) — there's nothing pre-existing under the old `iconTypes` path
  to move for any real user, since the feature only shipped one day before
  this spec and reached zero production users between the two.

### 4. Entry point: "Файлы меток" on the waypoints list screen

- `app/lib/waypoints/waypoints_list_screen.dart` gains an `AppBar` action
  (a new `IconButton`, e.g. `Icons.folder_open`, key
  `waypoint_files_button`) that pushes
  `MaterialPageRoute(builder: (_) => const MediaFileFolderScreen(title:
  'Файлы меток', subfolder: 'custom-types', allowedExtensions: ['png',
  'jpg', 'jpeg', 'svg']))`.

## Data flow summary

```
"Метки" tab → AppBar "Файлы меток" button
  → MediaFileFolderScreen(subfolder: 'custom-types', ...)
  → MediaFileFolderService.list() → mediafile/custom-types/*.{png,jpg,jpeg,svg}

Import tap → FilePicker.pickFiles(FileType.custom, allowedExtensions)
  → MediaFileFolderService.importFile(pickedPath)
  → copies bytes into mediafile/custom-types/<basename>
  → re-list()

(Existing, unaffected by this spec beyond the path rename:)
Waypoint form "Иконка" button → IconPickerSheet → IconLibraryScanner.scan()
  → mediafile/custom-types/*.{png,jpg,jpeg,svg}
```

## Testing

- `MediaFileFolderService`: unit tests against `MemoryFileSystem` (same
  pattern as `IconLibraryScanner`'s existing tests) — `list()` on an empty/
  populated folder, `importFile()` copying bytes correctly and overwriting
  an existing same-name file, `delete()` removing a file and tolerating a
  missing one.
- `MediaFileFolderScreen`: widget tests using an injected fake/service
  double — renders the list, empty state, delete confirmation flow
  (confirm vs. cancel), and import flow with a fake service whose
  `importFile` records the call (a real `FilePicker.pickFiles` call can't
  be driven in a widget test — the picker invocation itself is exercised
  only by manual device verification, consistent with this codebase's
  existing precedent for platform-channel-backed calls, e.g.
  `flutter_secure_storage`).
- `IconLibraryScanner`'s existing test suite continues to pass unmodified
  in behavior (only the literal path string changes, which its tests
  already parameterize via `baseDirectoryPath` — no test asserts the
  literal `iconTypes` substring, so no adjustment needed... verify this
  during implementation and update if any test does hardcode it).
- `flutter analyze` clean, full `flutter test` suite green.
- Manual device verification (this codebase's established pattern for
  anything a platform channel makes untestable under `flutter test`):
  open "Метки" → "Файлы меток", confirm the (renamed) folder's existing
  contents show up, import a PNG/SVG via the system picker, confirm it
  appears in the list and in the waypoint form's icon picker, delete it,
  confirm both screens agree it's gone.

## Open items for the implementation plan

- Exact icon for the AppBar action and empty-state copy — cosmetic,
  decided during implementation, not blocking design approval.
- Whether `MediaFileFolderService.importFile` should reject a source file
  whose extension isn't in `allowedExtensions` (defense in depth, since the
  picker itself already filters) — decided during implementation; either
  choice is compatible with this spec's goals.
