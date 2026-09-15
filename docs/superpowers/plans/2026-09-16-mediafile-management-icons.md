# mediafile file management (core) + custom-types entry point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user an in-app screen to see, import, and delete files in a `mediafile` subfolder — starting with the marker-icon folder (renamed `iconTypes` → `custom-types`), reachable from the "Метки" tab.

**Architecture:** A generic, format-agnostic `MediaFileFolderService` (list/import/delete against a named `mediafile` subfolder, same external-storage-first/app-docs-fallback resolution already proven by `IconLibraryScanner`) backs a generic `MediaFileFolderScreen` (list + import button + per-file delete). Import goes through Android's system file picker (`file_picker`, Storage Access Framework — no extra permissions). The existing icon folder path constant is renamed; nothing that reads it changes shape.

**Tech Stack:** Flutter, `file_picker` (new dependency, version verified against installed source), `package:file` (already a dependency, for the same `MemoryFileSystem`-testable seam used elsewhere in this codebase).

**Spec:** `docs/superpowers/specs/2026-09-16-mediafile-management-icons-design.md`

## Global Constraints

- No export (share/save-out) in this plan — deferred to a later, separate sub-project.
- Import uses Android's system file picker (Storage Access Framework via `file_picker`), not a direct listing of the OS Downloads folder.
- `mediafile/iconTypes` is renamed to `mediafile/custom-types` — path only; file formats (`.png`/`.jpg`/`.jpeg`/`.svg`) and every consumer of `IconLibraryScanner`/`IconFile` are otherwise unaffected.
- `FileType.custom` with an explicit `allowedExtensions` list is used for the picker (not `FileType.image`), since SVG's MIME registration under `image/*` is inconsistent across devices.

---

## Task 1: `MediaFileFolderService` (list/import/delete)

**Files:**
- Create: `app/lib/mediafile/mediafile_folder_service.dart`
- Modify: `app/pubspec.yaml` (add `file_picker: ^11.0.3` — needed by Task 2, but adding the dependency here keeps `pubspec.yaml` edits in the task that first needs *a* new external package; Task 2 doesn't need its own pubspec edit as a result)
- Test: `app/test/mediafile/mediafile_folder_service_test.dart`

**Interfaces:**
- Produces: `class MediaFileEntry { final String path; final String fileName; final int sizeBytes; }`; `class MediaFileFolderService { MediaFileFolderService({required String subfolder, FileSystem? fileSystem, String? baseDirectoryPath}); Future<List<MediaFileEntry>> list(); Future<void> importFile(String sourcePath); Future<void> delete(String fileName); }`.

This mirrors `IconLibraryScanner`'s constructor shape (`fileSystem`/`baseDirectoryPath` test seam) but is deliberately a separate, small class rather than a shared base — `IconLibraryScanner` is staying as-is except for one renamed constant (Task 3), and factoring out a shared root-resolution helper would mean touching already-shipped, already-tested code as a side effect of unrelated work. The ~6 lines of directory-resolution logic are duplicated on purpose.

- [ ] **Step 1: Add `file_picker` to `pubspec.yaml`**

Edit `app/pubspec.yaml`, in `dependencies:` (after `flutter_svg: ^2.2.4`):

```yaml
  flutter_svg: ^2.2.4
  file_picker: ^11.0.3
```

Run: `cd app && flutter pub get`
Expected: resolves cleanly. (Verified directly against the installed package source at version 11.0.3 during design — `FilePicker.pickFiles({FileType type, List<String>? allowedExtensions, bool allowMultiple})` returns `Future<FilePickerResult?>`; `FilePickerResult.files` is `List<PlatformFile>`; `PlatformFile.path`/`.name`/`.size`. The package ships its own Android manifest `<queries>` fragment — no manifest edit needed in this app.)

- [ ] **Step 2: Write the failing tests**

Create `app/test/mediafile/mediafile_folder_service_test.dart`:

```dart
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaFileFolderService', () {
    test('creates the folder when missing and returns an empty list', () async {
      final fs = MemoryFileSystem();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      final result = await service.list();

      expect(result, isEmpty);
      expect(fs.directory('/base/mediafile/custom-types').existsSync(), isTrue);
    });

    test('lists files with name and size, sorted by filename', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('zebra.png').writeAsBytesSync([1, 2, 3]);
      dir.childFile('arrow.svg').writeAsBytesSync([1, 2]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      final result = await service.list();

      expect(result.map((e) => e.fileName), ['arrow.svg', 'zebra.png']);
      expect(result.firstWhere((e) => e.fileName == 'arrow.svg').sizeBytes, 2);
      expect(result.firstWhere((e) => e.fileName == 'zebra.png').sizeBytes, 3);
    });

    test('importFile copies bytes from the source path into the folder under its basename', () async {
      final fs = MemoryFileSystem();
      fs.directory('/downloads').createSync(recursive: true);
      fs.file('/downloads/marker.svg').writeAsBytesSync([9, 9, 9]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.importFile('/downloads/marker.svg');

      final imported = fs.file('/base/mediafile/custom-types/marker.svg');
      expect(imported.existsSync(), isTrue);
      expect(imported.readAsBytesSync(), [9, 9, 9]);
    });

    test('importFile overwrites an existing file with the same name', () async {
      final fs = MemoryFileSystem();
      fs.directory('/downloads').createSync(recursive: true);
      fs.file('/downloads/marker.svg').writeAsBytesSync([9, 9, 9]);
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('marker.svg').writeAsBytesSync([1]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.importFile('/downloads/marker.svg');

      expect(fs.file('/base/mediafile/custom-types/marker.svg').readAsBytesSync(), [9, 9, 9]);
    });

    test('delete removes a file', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('marker.svg').createSync();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.delete('marker.svg');

      expect(fs.file('/base/mediafile/custom-types/marker.svg').existsSync(), isFalse);
    });

    test('delete tolerates a file that does not exist', () async {
      final fs = MemoryFileSystem();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.delete('does-not-exist.svg'); // must not throw
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd app && flutter test test/mediafile/mediafile_folder_service_test.dart`
Expected: FAIL — `package:app/mediafile/mediafile_folder_service.dart` doesn't exist yet.

- [ ] **Step 4: Implement `mediafile_folder_service.dart`**

```dart
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

class MediaFileEntry {
  const MediaFileEntry({required this.path, required this.fileName, required this.sizeBytes});

  final String path;
  final String fileName;
  final int sizeBytes;
}

/// Lists, imports into, and deletes from one named subfolder under the
/// device's mediafile root. Uses the same external-storage-first / app-docs
/// fallback resolution as IconLibraryScanner (app/lib/icons/
/// icon_library_scanner.dart) -- duplicated rather than shared, since that
/// class is otherwise unrelated shipped code.
class MediaFileFolderService {
  MediaFileFolderService({required this.subfolder, FileSystem? fileSystem, this.baseDirectoryPath})
      : _fileSystem = fileSystem ?? const LocalFileSystem();

  final String subfolder;
  final String? baseDirectoryPath;
  final FileSystem _fileSystem;

  Future<Directory> _resolveDirectory() async {
    final fixed = baseDirectoryPath;
    if (fixed != null) return _fileSystem.directory(fixed);

    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    return _fileSystem.directory('${base.path}/mediafile/$subfolder');
  }

  Future<List<MediaFileEntry>> list() async {
    final dir = await _resolveDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final entries = <MediaFileEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      entries.add(MediaFileEntry(path: entity.path, fileName: entity.basename, sizeBytes: entity.lengthSync()));
    }
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }

  Future<void> importFile(String sourcePath) async {
    final dir = await _resolveDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final source = _fileSystem.file(sourcePath);
    final bytes = await source.readAsBytes();
    await dir.childFile(source.basename).writeAsBytes(bytes);
  }

  Future<void> delete(String fileName) async {
    final dir = await _resolveDirectory();
    final target = dir.childFile(fileName);
    if (await target.exists()) {
      await target.delete();
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd app && flutter test test/mediafile/mediafile_folder_service_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
cd app
git add pubspec.yaml pubspec.lock lib/mediafile/mediafile_folder_service.dart test/mediafile/mediafile_folder_service_test.dart
git commit -m "feat: add generic mediafile subfolder service (list, import, delete)"
```

---

## Task 2: `MediaFileFolderScreen` (UI)

**Files:**
- Create: `app/lib/mediafile/mediafile_folder_screen.dart`
- Test: `app/test/mediafile/mediafile_folder_screen_test.dart`

**Interfaces:**
- Consumes: `MediaFileEntry`, `MediaFileFolderService` (Task 1).
- Produces: `class MediaFileFolderScreen extends StatefulWidget { const MediaFileFolderScreen({super.key, required String title, required String subfolder, required List<String> allowedExtensions, MediaFileFolderService? service}); }`. Widget keys: `mediafile_import_button`, `mediafile_entry_<fileName>` (per-row `ListTile`), `mediafile_delete_<fileName>` (per-row delete `IconButton`).

The optional `service` constructor parameter is the test seam (mirrors `IconPickerSheet`'s optional `scanner` parameter) — production call sites omit it and get a real `MediaFileFolderService(subfolder: ...)`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/mediafile/mediafile_folder_screen_test.dart`:

```dart
import 'package:app/mediafile/mediafile_folder_screen.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MediaFileFolderService _serviceWith(MemoryFileSystem fs, {List<String> fileNames = const []}) {
  final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
  for (final name in fileNames) {
    dir.childFile(name).writeAsBytesSync([1, 2, 3]);
  }
  return MediaFileFolderService(
    subfolder: 'custom-types',
    fileSystem: fs,
    baseDirectoryPath: '/base/mediafile/custom-types',
  );
}

Widget _harness(MediaFileFolderService service) => MaterialApp(
      home: MediaFileFolderScreen(
        title: 'Файлы меток',
        subfolder: 'custom-types',
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
        service: service,
      ),
    );

void main() {
  testWidgets('shows an empty state when the folder has no files', (tester) async {
    final service = _serviceWith(MemoryFileSystem());

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    expect(find.text('Здесь пока нет файлов'), findsOneWidget);
  });

  testWidgets('lists files by name', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg', 'camp.png']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsOneWidget);
    expect(find.byKey(const Key('mediafile_entry_camp.png')), findsOneWidget);
  });

  testWidgets('canceling the delete confirmation keeps the file', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mediafile_delete_marker.svg')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsOneWidget);
    expect(await service.list(), hasLength(1));
  });

  testWidgets('confirming the delete dialog removes the file from the list and the folder', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mediafile_delete_marker.svg')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsNothing);
    expect(find.text('Здесь пока нет файлов'), findsOneWidget);
    expect(await service.list(), isEmpty);
  });
}
```

Note: no test taps `mediafile_import_button` — the real import flow calls the static `FilePicker.pickFiles(...)`, which has no platform-channel mock under `flutter test` (same limitation this codebase already accepts for `flutter_secure_storage` and `getExternalStorageDirectory`). That path is covered by manual device verification only (see the plan's Final Verification section).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mediafile/mediafile_folder_screen_test.dart`
Expected: FAIL — `package:app/mediafile/mediafile_folder_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement `mediafile_folder_screen.dart`**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'mediafile_folder_service.dart';

class MediaFileFolderScreen extends StatefulWidget {
  const MediaFileFolderScreen({
    super.key,
    required this.title,
    required this.subfolder,
    required this.allowedExtensions,
    this.service,
  });

  final String title;
  final String subfolder;
  final List<String> allowedExtensions;
  final MediaFileFolderService? service;

  @override
  State<MediaFileFolderScreen> createState() => _MediaFileFolderScreenState();
}

class _MediaFileFolderScreenState extends State<MediaFileFolderScreen> {
  late final MediaFileFolderService _service =
      widget.service ?? MediaFileFolderService(subfolder: widget.subfolder);
  late Future<List<MediaFileEntry>> _future = _service.list();

  void _reload() {
    setState(() => _future = _service.list());
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions,
    );
    final path = result?.files.first.path;
    if (path == null) return;
    await _service.importFile(path);
    _reload();
  }

  Future<void> _delete(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить файл «$fileName»?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.delete(fileName);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('mediafile_import_button'),
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _import,
          ),
        ],
      ),
      body: FutureBuilder<List<MediaFileEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('Здесь пока нет файлов'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                key: Key('mediafile_entry_${entry.fileName}'),
                title: Text(entry.fileName),
                subtitle: Text('${(entry.sizeBytes / 1024).ceil()} КБ'),
                trailing: IconButton(
                  key: Key('mediafile_delete_${entry.fileName}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(entry.fileName),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/mediafile/mediafile_folder_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/mediafile/mediafile_folder_screen.dart test/mediafile/mediafile_folder_screen_test.dart
git commit -m "feat: add mediafile folder screen (list, import, delete)"
```

---

## Task 3: Rename `iconTypes` → `custom-types`

**Files:**
- Modify: `app/lib/icons/icon_library_scanner.dart`

**Interfaces:**
- No signature changes — `IconLibraryScanner`, `IconFile`, `iconFileFormatForPath` all keep their existing shapes. Only the private `_folderSuffix` string constant's value changes.

A repo-wide search confirms `'iconTypes'` (as a folder-name string) appears in exactly one file in `app/lib`: `icon_library_scanner.dart` itself, in the `_folderSuffix` constant. Every test that touches this class supplies its own `baseDirectoryPath` override (e.g. `'/base/mediafile/iconTypes'` in the existing test file) rather than relying on the real constant's value, so this rename does not require any test file changes to keep passing — but see Step 3 below for a cosmetic consistency pass.

- [ ] **Step 1: Change the constant**

In `app/lib/icons/icon_library_scanner.dart`, change:

```dart
  static const _folderSuffix = 'mediafile/iconTypes';
```

to:

```dart
  static const _folderSuffix = 'mediafile/custom-types';
```

- [ ] **Step 2: Run the existing scanner test suite to confirm nothing broke**

Run: `cd app && flutter test test/icons/icon_library_scanner_test.dart`
Expected: PASS, unmodified (these tests pass their own `baseDirectoryPath` and never reference `_folderSuffix`).

- [ ] **Step 3: Cosmetic consistency pass on the test file's literal paths**

`app/test/icons/icon_library_scanner_test.dart` currently uses `/base/mediafile/iconTypes` as its test-only `baseDirectoryPath` literal in two tests. This is not required to change for correctness (the tests don't reference the real constant), but leaving it would make the test file read as if the real folder were still named `iconTypes`, which is confusing for the next reader. Update both occurrences:

```dart
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/iconTypes');
```

→

```dart
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/custom-types');
```

(both the "creates the folder when missing" test and the "lists supported files" test), and update the matching `fs.directory(...)`/`dir` literal paths in the same two tests to `/base/mediafile/custom-types` as well, so every path in the file agrees.

- [ ] **Step 4: Run the tests to verify they still pass**

Run: `cd app && flutter test test/icons/icon_library_scanner_test.dart`
Expected: PASS (5 tests, unchanged count).

- [ ] **Step 5: Run the full suite for regressions**

Run: `cd app && flutter analyze && flutter test`
Expected: clean; no other test or production file references the old path (confirmed during design via a repo-wide search of `app/lib`).

- [ ] **Step 6: Commit**

```bash
cd app
git add lib/icons/icon_library_scanner.dart test/icons/icon_library_scanner_test.dart
git commit -m "refactor: rename mediafile/iconTypes to mediafile/custom-types"
```

---

## Task 4: Entry point — "Файлы меток" on the waypoints list screen

**Files:**
- Modify: `app/lib/waypoints/waypoints_list_screen.dart`
- Test: `app/test/waypoints/waypoints_list_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `MediaFileFolderScreen` (Task 2).

- [ ] **Step 1: Write the failing test**

Add to `app/test/waypoints/waypoints_list_screen_test.dart` (new imports `import 'package:app/mediafile/mediafile_folder_screen.dart';` at the top, and this case inside `main()`):

```dart
  testWidgets('AppBar action opens the icon files screen', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        ],
        child: const MaterialApp(home: WaypointsListScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_files_button')));
    // A real MediaFileFolderScreen resolves its folder via path_provider,
    // which has no platform-channel mock under flutter test (same
    // limitation already accepted elsewhere in this codebase, e.g.
    // IconLibraryScanner's default constructor) -- a single pump is enough
    // to prove the navigation happened, without waiting for that call to
    // settle.
    await tester.pump();

    expect(find.byType(MediaFileFolderScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/waypoints/waypoints_list_screen_test.dart`
Expected: FAIL — no widget with key `waypoint_files_button` exists yet.

- [ ] **Step 3: Add the AppBar action**

Modify `app/lib/waypoints/waypoints_list_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/waypoint_icon_assignments_controller.dart';
import '../mediafile/mediafile_folder_screen.dart';
import 'waypoint_actions.dart';
import 'waypoint_color.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';

class WaypointsListScreen extends ConsumerStatefulWidget {
  const WaypointsListScreen({super.key});

  @override
  ConsumerState<WaypointsListScreen> createState() => _WaypointsListScreenState();
}

class _WaypointsListScreenState extends ConsumerState<WaypointsListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(waypointsControllerProvider.notifier).loadWaypoints());
    Future.microtask(() => ref.read(waypointIconAssignmentsControllerProvider.notifier).load());
  }

  void _openFiles() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MediaFileFolderScreen(
          title: 'Файлы меток',
          subfolder: 'custom-types',
          allowedExtensions: ['png', 'jpg', 'jpeg', 'svg'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waypoints = ref.watch(waypointsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Метки'),
        actions: [
          IconButton(
            key: const Key('waypoint_files_button'),
            icon: const Icon(Icons.folder_open),
            onPressed: _openFiles,
          ),
        ],
      ),
      body: waypoints.isEmpty
          ? const Center(child: Text('Пока нет меток'))
          : ListView.builder(
              itemCount: waypoints.length,
              itemBuilder: (context, index) {
                final waypoint = waypoints[index];
                final color = colorFromHex(
                  waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
                );
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    key: Key('waypoint_card_${waypoint.id}'),
                    leading: CircleAvatar(backgroundColor: color, radius: 12),
                    title: Text(waypoint.name),
                    subtitle: Text(waypointTypeLabels[waypoint.type] ?? waypoint.type),
                    onTap: () => showWaypointDetails(context, ref, waypoint),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/waypoints/waypoints_list_screen_test.dart`
Expected: PASS (3 tests, 1 new).

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` clean; full suite green.

- [ ] **Step 6: Commit**

```bash
cd app
git add lib/waypoints/waypoints_list_screen.dart test/waypoints/waypoints_list_screen_test.dart
git commit -m "feat: add \"Файлы меток\" entry point to the waypoints list screen"
```

---

## Final Verification

- [ ] Run `cd app && flutter analyze` — must be clean.
- [ ] Run `cd app && flutter test` — full suite green.
- [ ] Confirm no files under `api/` were touched (`git diff --stat main -- api/` should be empty) — this feature is frontend-only per the spec.
- [ ] Manual device verification (per the spec's Testing section — nothing in this plan can exercise the real `file_picker` platform channel under `flutter test`):
  1. Open "Метки" tab → tap the new folder-icon AppBar action → confirm the (renamed) `custom-types` folder's existing contents show up under "Файлы меток".
  2. Tap "Импорт" → pick a PNG or SVG from the system file picker → confirm it appears in the list.
  3. Open the waypoint create/edit form's icon picker → confirm the just-imported file appears there too (same folder, same scanner).
  4. Delete the file from "Файлы меток" → confirm it disappears from both this screen and the waypoint form's icon picker.
