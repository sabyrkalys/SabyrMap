# Waypoint custom icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a waypoint show a real image marker on the map (PNG/JPEG/SVG, tintable for SVG), sourced from files the user drops into a device folder — no backend changes, no in-app upload UI.

**Architecture:** A local file scanner reads `mediafile/iconTypes/` on demand for the form's icon picker. A `WaypointIconAssignmentsController` (Riverpod `Notifier`) persists the chosen filename per waypoint id via `flutter_secure_storage` and is the single reactive source other widgets read/write through. `MapScreen` gains a `SymbolManager` path alongside its existing `CircleManager`: waypoints with an assignment render as an image `Symbol` (rasterized/tinted on demand and cached by `IconImageCache`), everything else keeps rendering as the existing colored `Circle`.

**Tech Stack:** Flutter, `flutter_riverpod`, `maplibre_gl` 0.26.2 (`SymbolManager`/`addImage`), `flutter_secure_storage` (already a dependency, reused — no new persistence dependency), `flutter_svg` (new), `path_provider` + `file` (already transitive, promoted to direct dependencies).

**Spec:** `docs/superpowers/specs/2026-09-15-waypoint-custom-icons-design.md`

## Global Constraints

- Icon folder path: `<external files dir>/mediafile/iconTypes/` (falls back to the app's documents directory + the same suffix when external storage is unavailable, e.g. desktop dev runs).
- Supported extensions: `.png`, `.jpg`, `.jpeg`, `.svg` (case-insensitive); everything else in the folder is ignored.
- Icon choice is local-only: stored via `flutter_secure_storage`, never sent to the backend, never read from it.
- SVG icons are tinted to the waypoint's effective color (`waypoint.color ?? waypointTypeColors[type]`); PNG/JPEG icons render as-is (no tint) and the form's color picker is hidden when one is selected.
- Every rendered marker bitmap (raster or SVG) is normalized to a fixed 48×48 canvas (aspect-fit, centered) before being registered with `addImage`, so `SymbolOptions.iconSize` can stay a single constant regardless of the source file's native dimensions.
- Rescanning the icon folder happens every time the picker sheet opens (no caching of the file listing itself).

---

## Task 1: Icon file model + folder scanner

**Files:**
- Create: `app/lib/icons/icon_library_scanner.dart`
- Modify: `app/pubspec.yaml` (add `path_provider`, `file` as direct dependencies — both already present transitively per `pubspec.lock`, so `flutter pub get` should not change their resolved versions)
- Test: `app/test/icons/icon_library_scanner_test.dart`

**Interfaces:**
- Produces: `enum IconFileFormat { svg, raster }`; `class IconFile { final String path; final String fileName; final String displayName; final IconFileFormat format; }`; `IconFileFormat? iconFileFormatForPath(String path)` (top-level, pure); `class IconLibraryScanner { IconLibraryScanner({FileSystem? fileSystem}); Future<Directory> resolveBaseDirectory(); Future<List<IconFile>> scan(); }`.

- [ ] **Step 1: Add `path_provider` and `file` as direct dependencies**

Edit `app/pubspec.yaml`, in the `dependencies:` block (after `flutter_compass: ^0.8.1`):

```yaml
  flutter_compass: ^0.8.1
  path_provider: ^2.1.5
  file: ^7.0.1
```

Run: `cd app && flutter pub get`
Expected: resolves cleanly (both already appear as transitive entries in `pubspec.lock`, so no version conflicts).

- [ ] **Step 2: Write the failing tests for `iconFileFormatForPath` and `IconLibraryScanner.scan`**

Create `app/test/icons/icon_library_scanner_test.dart`:

```dart
import 'package:app/icons/icon_library_scanner.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iconFileFormatForPath', () {
    test('recognizes svg', () {
      expect(iconFileFormatForPath('a/volcano.svg'), IconFileFormat.svg);
      expect(iconFileFormatForPath('a/volcano.SVG'), IconFileFormat.svg);
    });

    test('recognizes png and jpg/jpeg as raster', () {
      expect(iconFileFormatForPath('a/b.png'), IconFileFormat.raster);
      expect(iconFileFormatForPath('a/b.JPG'), IconFileFormat.raster);
      expect(iconFileFormatForPath('a/b.jpeg'), IconFileFormat.raster);
    });

    test('returns null for unsupported extensions', () {
      expect(iconFileFormatForPath('a/b.gif'), isNull);
      expect(iconFileFormatForPath('a/b.txt'), isNull);
      expect(iconFileFormatForPath('a/b'), isNull);
    });
  });

  group('IconLibraryScanner', () {
    test('creates the folder when missing and returns an empty list', () async {
      final fs = MemoryFileSystem();
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/iconTypes');

      final result = await scanner.scan();

      expect(result, isEmpty);
      expect(fs.directory('/base/mediafile/iconTypes').existsSync(), isTrue);
    });

    test('lists supported files sorted by filename, ignoring unsupported ones', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/iconTypes')..createSync(recursive: true);
      dir.childFile('zebra.png').createSync();
      dir.childFile('arrow.svg').createSync();
      dir.childFile('notes.txt').createSync();
      dir.childFile('camp.jpeg').createSync();
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/iconTypes');

      final result = await scanner.scan();

      expect(result.map((f) => f.fileName), ['arrow.svg', 'camp.jpeg', 'zebra.png']);
      expect(result.map((f) => f.displayName), ['arrow', 'camp', 'zebra']);
      expect(result[0].format, IconFileFormat.svg);
      expect(result[1].format, IconFileFormat.raster);
    });
  });
}
```

- [ ] **Step 2b: Run the tests to verify they fail**

Run: `cd app && flutter test test/icons/icon_library_scanner_test.dart`
Expected: FAIL — `package:app/icons/icon_library_scanner.dart` doesn't exist yet.

- [ ] **Step 3: Implement `icon_library_scanner.dart`**

```dart
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

enum IconFileFormat { svg, raster }

class IconFile {
  const IconFile({required this.path, required this.fileName, required this.displayName, required this.format});

  final String path;
  final String fileName;
  final String displayName;
  final IconFileFormat format;
}

/// Pure classification of a file path's extension. Extracted as a top-level
/// function so it's unit-testable without touching any filesystem.
IconFileFormat? iconFileFormatForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.svg')) return IconFileFormat.svg;
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return IconFileFormat.raster;
  return null;
}

/// Scans the device folder the user drops icon files into. Takes an
/// injectable [FileSystem] (defaulting to the real one) and an optional
/// fixed [baseDirectoryPath] so tests can point it at a [MemoryFileSystem]
/// path without touching real device storage or platform channels.
class IconLibraryScanner {
  IconLibraryScanner({FileSystem? fileSystem, this.baseDirectoryPath})
      : _fileSystem = fileSystem ?? const LocalFileSystem();

  final FileSystem _fileSystem;
  final String? baseDirectoryPath;

  static const _folderSuffix = 'mediafile/iconTypes';

  Future<Directory> resolveBaseDirectory() async {
    final fixed = baseDirectoryPath;
    if (fixed != null) return _fileSystem.directory(fixed);

    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    return _fileSystem.directory('${base.path}/$_folderSuffix');
  }

  Future<List<IconFile>> scan() async {
    final dir = await resolveBaseDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final entries = <IconFile>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final format = iconFileFormatForPath(entity.path);
      if (format == null) continue;
      final fileName = entity.basename;
      final dot = fileName.lastIndexOf('.');
      final displayName = dot > 0 ? fileName.substring(0, dot) : fileName;
      entries.add(IconFile(path: entity.path, fileName: fileName, displayName: displayName, format: format));
    }
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }
}
```

Note: `getExternalStorageDirectory()` (from `path_provider`) returns `Directory?` and resolves to `.../Android/data/<applicationId>/files` on Android; on platforms where it returns `null` (iOS, desktop, and any platform without an "external storage" concept) the code falls back to `getApplicationDocumentsDirectory()`. `entity.basename` comes from `package:file`'s `FileSystemEntity` extension — matches `path_provider`'s real `Directory`/`File` types via the `LocalFileSystem` wrapper.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/icons/icon_library_scanner_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd app
git add pubspec.yaml pubspec.lock lib/icons/icon_library_scanner.dart test/icons/icon_library_scanner_test.dart
git commit -m "feat: add icon file model and mediafile/iconTypes folder scanner"
```

---

## Task 2: Local icon-assignment persistence

**Files:**
- Create: `app/lib/icons/waypoint_icon_store.dart`
- Create: `app/test/icons/fakes.dart`
- Test: `app/test/icons/waypoint_icon_store_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `abstract class WaypointIconStore { Future<String?> iconFor(String waypointId); Future<void> setIcon(String waypointId, String? fileName); Future<Map<String, String>> readAll(); }`; `class SecureWaypointIconStore implements WaypointIconStore`; `final waypointIconStoreProvider = Provider<WaypointIconStore>(...)`; `class FakeWaypointIconStore implements WaypointIconStore` (test double, in `test/icons/fakes.dart`).

This mirrors `TokenStorage`/`SecureTokenStorage` (`app/lib/auth/token_storage.dart`) exactly, including the precedent that the real `flutter_secure_storage`-backed implementation has no dedicated unit test (untestable without mocking a platform channel) — only the interface is exercised, via the fake, in later tasks' widget/controller tests.

- [ ] **Step 1: Write the failing test for the store's contract, via the fake**

Create `app/test/icons/fakes.dart`:

```dart
import 'package:app/icons/waypoint_icon_store.dart';

class FakeWaypointIconStore implements WaypointIconStore {
  final Map<String, String> icons = {};

  @override
  Future<String?> iconFor(String waypointId) async => icons[waypointId];

  @override
  Future<void> setIcon(String waypointId, String? fileName) async {
    if (fileName == null) {
      icons.remove(waypointId);
    } else {
      icons[waypointId] = fileName;
    }
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(icons);
}
```

Create `app/test/icons/waypoint_icon_store_test.dart`:

```dart
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('WaypointIconStore contract (via FakeWaypointIconStore)', () {
    late WaypointIconStore store;

    setUp(() => store = FakeWaypointIconStore());

    test('iconFor returns null when nothing is set', () async {
      expect(await store.iconFor('w1'), isNull);
    });

    test('setIcon then iconFor round-trips', () async {
      await store.setIcon('w1', 'volcano.svg');
      expect(await store.iconFor('w1'), 'volcano.svg');
    });

    test('setIcon with null clears a previous assignment', () async {
      await store.setIcon('w1', 'volcano.svg');
      await store.setIcon('w1', null);
      expect(await store.iconFor('w1'), isNull);
    });

    test('readAll returns every assignment', () async {
      await store.setIcon('w1', 'volcano.svg');
      await store.setIcon('w2', 'camp.png');
      expect(await store.readAll(), {'w1': 'volcano.svg', 'w2': 'camp.png'});
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/icons/waypoint_icon_store_test.dart`
Expected: FAIL — `package:app/icons/waypoint_icon_store.dart` doesn't exist yet.

- [ ] **Step 3: Implement `waypoint_icon_store.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class WaypointIconStore {
  Future<String?> iconFor(String waypointId);
  Future<void> setIcon(String waypointId, String? fileName);
  Future<Map<String, String>> readAll();
}

/// Persists which local icon file (if any) is assigned to each waypoint id.
/// Local-only by design: never sent to the backend, never read from it --
/// see docs/superpowers/specs/2026-09-15-waypoint-custom-icons-design.md.
class SecureWaypointIconStore implements WaypointIconStore {
  SecureWaypointIconStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'waypoint_icon_';

  final FlutterSecureStorage _storage;

  String _keyFor(String waypointId) => '$_prefix$waypointId';

  @override
  Future<String?> iconFor(String waypointId) => _storage.read(key: _keyFor(waypointId));

  @override
  Future<void> setIcon(String waypointId, String? fileName) {
    final key = _keyFor(waypointId);
    if (fileName == null) return _storage.delete(key: key);
    return _storage.write(key: key, value: fileName);
  }

  @override
  Future<Map<String, String>> readAll() async {
    final all = await _storage.readAll();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith(_prefix)) entry.key.substring(_prefix.length): entry.value,
    };
  }
}

final waypointIconStoreProvider = Provider<WaypointIconStore>((ref) => SecureWaypointIconStore());
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/icons/waypoint_icon_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/icons/waypoint_icon_store.dart test/icons/fakes.dart test/icons/waypoint_icon_store_test.dart
git commit -m "feat: add local, secure-storage-backed waypoint icon assignment store"
```

---

## Task 3: Reactive assignments controller

**Files:**
- Create: `app/lib/icons/waypoint_icon_assignments_controller.dart`
- Test: `app/test/icons/waypoint_icon_assignments_controller_test.dart`

**Interfaces:**
- Consumes: `WaypointIconStore` (Task 2) via `waypointIconStoreProvider`; `FakeWaypointIconStore` (Task 2) in tests.
- Produces: `final waypointIconAssignmentsControllerProvider = NotifierProvider<WaypointIconAssignmentsController, Map<String, String>>(...)`; `class WaypointIconAssignmentsController extends Notifier<Map<String, String>> { Future<void> load(); Future<void> setIcon(String waypointId, String? fileName); }`. State: `Map<String, String>` of `waypointId -> fileName` for every *locally known* assignment (absence = "no icon, use the colored circle").

This is the single reactive seam every consumer (MapScreen, `waypoint_actions.dart`, `WaypointsListScreen`) reads/writes through — mirrors the existing `WaypointsController` pattern (`app/lib/waypoints/waypoints_controller.dart`) so a `setIcon` call is immediately visible to anything with `ref.watch`/`ref.listen` on this provider, without re-reading secure storage.

- [ ] **Step 1: Write the failing tests**

Create `app/test/icons/waypoint_icon_assignments_controller_test.dart`:

```dart
import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('build() starts empty', () {
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(FakeWaypointIconStore())],
    );
    addTearDown(container.dispose);

    expect(container.read(waypointIconAssignmentsControllerProvider), isEmpty);
  });

  test('load() pulls every existing assignment from the store', () async {
    final store = FakeWaypointIconStore()..icons.addAll({'w1': 'volcano.svg'});
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(waypointIconAssignmentsControllerProvider.notifier).load();

    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'volcano.svg'});
  });

  test('setIcon updates both the store and the in-memory state immediately', () async {
    final store = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(waypointIconAssignmentsControllerProvider.notifier).setIcon('w1', 'camp.png');

    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'camp.png'});
    expect(await store.iconFor('w1'), 'camp.png');
  });

  test('setIcon with null clears the assignment from state and store', () async {
    final store = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(waypointIconAssignmentsControllerProvider.notifier);
    await notifier.setIcon('w1', 'camp.png');

    await notifier.setIcon('w1', null);

    expect(container.read(waypointIconAssignmentsControllerProvider), isEmpty);
    expect(await store.iconFor('w1'), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/icons/waypoint_icon_assignments_controller_test.dart`
Expected: FAIL — module doesn't exist yet.

- [ ] **Step 3: Implement `waypoint_icon_assignments_controller.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoint_icon_store.dart';

final waypointIconAssignmentsControllerProvider =
    NotifierProvider<WaypointIconAssignmentsController, Map<String, String>>(
  WaypointIconAssignmentsController.new,
);

class WaypointIconAssignmentsController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  WaypointIconStore get _store => ref.read(waypointIconStoreProvider);

  Future<void> load() async {
    state = await _store.readAll();
  }

  Future<void> setIcon(String waypointId, String? fileName) async {
    await _store.setIcon(waypointId, fileName);
    final next = Map.of(state);
    if (fileName == null) {
      next.remove(waypointId);
    } else {
      next[waypointId] = fileName;
    }
    state = next;
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/icons/waypoint_icon_assignments_controller_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/icons/waypoint_icon_assignments_controller.dart test/icons/waypoint_icon_assignments_controller_test.dart
git commit -m "feat: add reactive controller for local waypoint icon assignments"
```

---

## Task 4: Icon bitmap rendering (raster normalize + SVG tint)

**Files:**
- Create: `app/lib/icons/icon_renderer.dart`
- Modify: `app/pubspec.yaml` (add `flutter_svg`)
- Test: `app/test/icons/icon_renderer_test.dart`

**Interfaces:**
- Consumes: `IconFile`, `IconFileFormat` (Task 1).
- Produces: `const int kIconCanvasSize = 48;`; `Future<Uint8List> renderIconBytes(IconFile icon, String? colorHex)` — always returns a `kIconCanvasSize x kIconCanvasSize` PNG; raster input is aspect-fit/centered/re-encoded (no tint); SVG input is aspect-fit/centered/rasterized with a `srcIn` tint using `colorHex` (defaulting to black if `null`).

- [ ] **Step 1: Add `flutter_svg`**

Edit `app/pubspec.yaml`, in `dependencies:` (after the `file:` line added in Task 1):

```yaml
  file: ^7.0.1
  flutter_svg: ^2.2.4
```

Run: `cd app && flutter pub get`
Expected: resolves cleanly, adds `flutter_svg` and its transitive deps (`vector_graphics`, `vector_graphics_codec`, `vector_graphics_compiler`) to `pubspec.lock`.

- [ ] **Step 2: Write the failing tests**

Create `app/test/icons/icon_renderer_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/icon_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('icon_renderer_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('raster input is re-encoded to the canonical square canvas size', () async {
    // A minimal 2x1 red-then-blue PNG, built at runtime via dart:ui so the
    // test has no binary fixture to maintain.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..color = const ui.Color(0xFFFF0000));
    canvas.drawRect(const Rect.fromLTWH(1, 0, 1, 1), ui.Paint()..color = const ui.Color(0xFF0000FF));
    final srcImage = await recorder.endRecording().toImage(2, 1);
    final srcPng = (await srcImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final file = File('${tempDir.path}/two_by_one.png')..writeAsBytesSync(srcPng);
    final icon = IconFile(path: file.path, fileName: 'two_by_one.png', displayName: 'two_by_one', format: IconFileFormat.raster);

    final bytes = await renderIconBytes(icon, null);
    final image = await _decode(bytes);

    expect(image.width, kIconCanvasSize);
    expect(image.height, kIconCanvasSize);
  });

  test('svg input is tinted to the requested color', () async {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<rect width="10" height="10" fill="#FF0000"/></svg>';
    final file = File('${tempDir.path}/marker.svg')..writeAsStringSync(svg);
    final icon = IconFile(path: file.path, fileName: 'marker.svg', displayName: 'marker', format: IconFileFormat.svg);

    final bytes = await renderIconBytes(icon, '#00FF00');
    final image = await _decode(bytes);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final centerPixel = (kIconCanvasSize ~/ 2) * kIconCanvasSize + (kIconCanvasSize ~/ 2);
    final r = pixels!.getUint8(centerPixel * 4);
    final g = pixels.getUint8(centerPixel * 4 + 1);
    final b = pixels.getUint8(centerPixel * 4 + 2);
    final a = pixels.getUint8(centerPixel * 4 + 3);

    expect(image.width, kIconCanvasSize);
    expect(a, greaterThan(0));
    expect(g, greaterThan(200));
    expect(r, lessThan(50));
    expect(b, lessThan(50));
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd app && flutter test test/icons/icon_renderer_test.dart`
Expected: FAIL — `package:app/icons/icon_renderer.dart` doesn't exist yet.

- [ ] **Step 4: Implement `icon_renderer.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../waypoints/waypoint_color.dart';
import 'icon_library_scanner.dart';

/// Every rendered marker bitmap (raster or SVG) is normalized to this square
/// size before being registered with MapLibre's addImage, so callers never
/// need to compute a per-image iconSize -- see the design spec's "Global
/// Constraints".
const int kIconCanvasSize = 48;

/// Renders [icon] to a `kIconCanvasSize x kIconCanvasSize` PNG. Raster
/// (`png`/`jpg`/`jpeg`) input is aspect-fit and centered, unmodified in
/// color. SVG input is aspect-fit, centered, and tinted a single flat color
/// (via a `srcIn` blend) equal to [colorHex] (`#000000` if null) -- correct
/// only for monochrome glyph-style SVGs, which is what this feature targets.
Future<Uint8List> renderIconBytes(IconFile icon, String? colorHex) {
  if (icon.format == IconFileFormat.raster) return _renderRaster(icon);
  return _renderSvg(icon, colorHex);
}

Future<Uint8List> _renderRaster(IconFile icon) async {
  final bytes = await File(icon.path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final longestSide = image.width > image.height ? image.width : image.height;
  final scale = kIconCanvasSize / longestSide;
  final dx = (kIconCanvasSize - image.width * scale) / 2;
  final dy = (kIconCanvasSize - image.height * scale) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()));
  canvas.translate(dx, dy);
  canvas.scale(scale);
  canvas.drawImage(image, Offset.zero, ui.Paint());
  image.dispose();

  final output = await recorder.endRecording().toImage(kIconCanvasSize, kIconCanvasSize);
  final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  return byteData!.buffer.asUint8List();
}

Future<Uint8List> _renderSvg(IconFile icon, String? colorHex) async {
  final svgString = await File(icon.path).readAsString();
  final tint = colorFromHex(colorHex ?? '#000000');
  final pictureInfo = await vg.loadPicture(SvgStringLoader(svgString), null);

  final srcW = pictureInfo.size.width > 0 ? pictureInfo.size.width : kIconCanvasSize.toDouble();
  final srcH = pictureInfo.size.height > 0 ? pictureInfo.size.height : kIconCanvasSize.toDouble();
  final longestSide = srcW > srcH ? srcW : srcH;
  final scale = kIconCanvasSize / longestSide;
  final dx = (kIconCanvasSize - srcW * scale) / 2;
  final dy = (kIconCanvasSize - srcH * scale) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()));
  canvas.saveLayer(
    const Rect.fromLTWH(0, 0, kIconCanvasSize.toDouble(), kIconCanvasSize.toDouble()),
    ui.Paint()..colorFilter = ui.ColorFilter.mode(tint, ui.BlendMode.srcIn),
  );
  canvas.translate(dx, dy);
  canvas.scale(scale);
  canvas.drawPicture(pictureInfo.picture);
  canvas.restore();
  pictureInfo.picture.dispose();

  final output = await recorder.endRecording().toImage(kIconCanvasSize, kIconCanvasSize);
  final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  return byteData!.buffer.asUint8List();
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd app && flutter test test/icons/icon_renderer_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd app
git add pubspec.yaml pubspec.lock lib/icons/icon_renderer.dart test/icons/icon_renderer_test.dart
git commit -m "feat: add icon bitmap renderer (raster normalize, SVG tint)"
```

---

## Task 5: Per-image registration cache

**Files:**
- Create: `app/lib/icons/icon_image_cache.dart`
- Test: `app/test/icons/icon_image_cache_test.dart`

**Interfaces:**
- Consumes: `IconFile`, `IconFileFormat` (Task 1); `renderIconBytes` (Task 4, injectable for tests).
- Produces: `typedef AddImageFn = Future<void> Function(String name, Uint8List bytes);`; `typedef RenderIconFn = Future<Uint8List> Function(IconFile icon, String? colorHex);`; `String symbolImageName(IconFile icon, String? colorHex)` (pure); `class IconImageCache { IconImageCache({required AddImageFn addImage, RenderIconFn render = renderIconBytes}); Future<String> resolve(IconFile icon, String? colorHex); void clear(); }`.

`IconImageCache` takes a plain `addImage` callback rather than a `MapLibreMapController` so it's fully unit-testable without a real platform view (the existing codebase never exercises `MapLibreMapController`-dependent logic in tests either — see the comments in `map_screen_test.dart` about manual device verification — this cache is deliberately designed to be the one piece of the icon-rendering path that *can* be tested without one).

- [ ] **Step 1: Write the failing tests**

Create `app/test/icons/icon_image_cache_test.dart`:

```dart
import 'dart:typed_data';

import 'package:app/icons/icon_image_cache.dart';
import 'package:app/icons/icon_library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rasterIcon = IconFile(path: '/x/camp.png', fileName: 'camp.png', displayName: 'camp', format: IconFileFormat.raster);
  final svgIcon = IconFile(path: '/x/marker.svg', fileName: 'marker.svg', displayName: 'marker', format: IconFileFormat.svg);

  group('symbolImageName', () {
    test('raster name ignores color', () {
      expect(symbolImageName(rasterIcon, '#FF0000'), 'icon_raster_camp.png');
      expect(symbolImageName(rasterIcon, null), 'icon_raster_camp.png');
    });

    test('svg name includes the color', () {
      expect(symbolImageName(svgIcon, '#FF0000'), 'icon_svg_marker.svg_#FF0000');
      expect(symbolImageName(svgIcon, '#00FF00'), 'icon_svg_marker.svg_#00FF00');
    });
  });

  group('IconImageCache', () {
    test('renders and registers on first resolve', () async {
      final addImageCalls = <(String, Uint8List)>[];
      var renderCalls = 0;
      final cache = IconImageCache(
        addImage: (name, bytes) async => addImageCalls.add((name, bytes)),
        render: (icon, colorHex) async {
          renderCalls++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );

      final name = await cache.resolve(svgIcon, '#FF0000');

      expect(name, 'icon_svg_marker.svg_#FF0000');
      expect(renderCalls, 1);
      expect(addImageCalls, hasLength(1));
      expect(addImageCalls.single.$1, name);
    });

    test('a second resolve for the same (icon, color) pair is a cache hit', () async {
      var renderCalls = 0;
      final cache = IconImageCache(
        addImage: (_, __) async {},
        render: (icon, colorHex) async {
          renderCalls++;
          return Uint8List.fromList([1]);
        },
      );

      await cache.resolve(svgIcon, '#FF0000');
      await cache.resolve(svgIcon, '#FF0000');

      expect(renderCalls, 1);
    });

    test('a different color for the same svg is a cache miss', () async {
      var renderCalls = 0;
      final cache = IconImageCache(addImage: (_, __) async {}, render: (icon, colorHex) async {
        renderCalls++;
        return Uint8List.fromList([1]);
      });

      await cache.resolve(svgIcon, '#FF0000');
      await cache.resolve(svgIcon, '#00FF00');

      expect(renderCalls, 2);
    });

    test('clear() forgets registrations, forcing a re-render on next resolve', () async {
      var renderCalls = 0;
      final cache = IconImageCache(addImage: (_, __) async {}, render: (icon, colorHex) async {
        renderCalls++;
        return Uint8List.fromList([1]);
      });
      await cache.resolve(svgIcon, '#FF0000');

      cache.clear();
      await cache.resolve(svgIcon, '#FF0000');

      expect(renderCalls, 2);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/icons/icon_image_cache_test.dart`
Expected: FAIL — `package:app/icons/icon_image_cache.dart` doesn't exist yet.

- [ ] **Step 3: Implement `icon_image_cache.dart`**

```dart
import 'dart:typed_data';

import 'icon_library_scanner.dart';
import 'icon_renderer.dart';

typedef AddImageFn = Future<void> Function(String name, Uint8List bytes);
typedef RenderIconFn = Future<Uint8List> Function(IconFile icon, String? colorHex);

/// Pure naming rule for a registered MapLibre image: raster icons ignore
/// color (never tinted), SVG icons are keyed by color too since a re-tint
/// needs a distinct registered image.
String symbolImageName(IconFile icon, String? colorHex) {
  if (icon.format == IconFileFormat.raster) return 'icon_raster_${icon.fileName}';
  return 'icon_svg_${icon.fileName}_${colorHex ?? ''}';
}

/// Registers each distinct (icon file, color) pair with the map's style at
/// most once. Takes a plain [AddImageFn] callback instead of a
/// MapLibreMapController so this class is unit-testable without a real
/// platform view.
class IconImageCache {
  IconImageCache({required AddImageFn addImage, RenderIconFn render = renderIconBytes})
      : _addImage = addImage,
        _render = render;

  final AddImageFn _addImage;
  final RenderIconFn _render;
  final Set<String> _registered = {};

  Future<String> resolve(IconFile icon, String? colorHex) async {
    final name = symbolImageName(icon, colorHex);
    if (_registered.contains(name)) return name;
    final effectiveColor = icon.format == IconFileFormat.svg ? colorHex : null;
    final bytes = await _render(icon, effectiveColor);
    await _addImage(name, bytes);
    _registered.add(name);
    return name;
  }

  /// Call on every style reload -- MapLibre's registered images don't
  /// survive it, so this cache's bookkeeping must be dropped too.
  void clear() => _registered.clear();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/icons/icon_image_cache_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/icons/icon_image_cache.dart test/icons/icon_image_cache_test.dart
git commit -m "feat: add per-(icon,color) MapLibre image registration cache"
```

---

## Task 6: Icon picker UI in the waypoint form

**Files:**
- Create: `app/lib/icons/icon_picker_sheet.dart`
- Modify: `app/lib/waypoints/waypoint_form_sheet.dart`
- Test: `app/test/icons/icon_picker_sheet_test.dart`
- Test: `app/test/waypoints/waypoint_form_sheet_test.dart` (extend)

**Interfaces:**
- Consumes: `IconFile`, `IconLibraryScanner` (Task 1).
- Produces: `class IconPickResult { const IconPickResult.file(String fileName) : fileName = fileName; const IconPickResult.reset() : fileName = null; final String? fileName; }`; `Future<IconPickResult?> showIconPickerSheet(BuildContext context, {IconLibraryScanner? scanner})`; `WaypointFormResult` gains `final String? iconFileName;`; `showWaypointFormSheet` gains an optional `String? initialIconFileName` parameter.

`showIconPickerSheet` returning `null` means "sheet dismissed without a choice" (form state unchanged); `IconPickResult.reset()` means "explicitly chose Стандартная" (clears the pick); `IconPickResult.file(name)` means "picked this file".

- [ ] **Step 1: Write the failing test for the picker sheet**

Create `app/test/icons/icon_picker_sheet_test.dart`:

```dart
import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/icon_picker_sheet.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(IconLibraryScanner scanner, ValueChanged<IconPickResult?> onResult) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await showIconPickerSheet(context, scanner: scanner);
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a "Стандартная" tile plus every scanned file, labeled without extension', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    dir.childFile('marker.svg').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');

    await tester.pumpWidget(_harness(scanner, (_) {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Стандартная'), findsOneWidget);
    expect(find.text('camp'), findsOneWidget);
    expect(find.text('marker'), findsOneWidget);
  });

  testWidgets('tapping a file tile returns IconPickResult.file with its filename', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result;

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();

    expect(result?.fileName, 'camp.png');
  });

  testWidgets('tapping "Стандартная" returns a reset result', (tester) async {
    final fs = MemoryFileSystem();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result = const IconPickResult.file('sentinel.png');

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_default_tile')));
    await tester.pumpAndSettle();

    expect(result?.fileName, isNull);
  });

  testWidgets('dismissing without a choice returns null', (tester) async {
    final fs = MemoryFileSystem();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result = const IconPickResult.file('sentinel.png');

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/icons/icon_picker_sheet_test.dart`
Expected: FAIL — `package:app/icons/icon_picker_sheet.dart` doesn't exist yet.

- [ ] **Step 3: Implement `icon_picker_sheet.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'icon_library_scanner.dart';

class IconPickResult {
  const IconPickResult.file(String fileName) : fileName = fileName;
  const IconPickResult.reset() : fileName = null;

  final String? fileName;
}

Future<IconPickResult?> showIconPickerSheet(BuildContext context, {IconLibraryScanner? scanner}) {
  return showModalBottomSheet<IconPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _IconPickerSheet(scanner: scanner ?? IconLibraryScanner()),
  );
}

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet({required this.scanner});

  final IconLibraryScanner scanner;

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  late final Future<List<IconFile>> _future = widget.scanner.scan();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: FutureBuilder<List<IconFile>>(
          future: _future,
          builder: (context, snapshot) {
            final files = snapshot.data ?? const <IconFile>[];
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
              itemCount: files.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Tile(
                    key: const Key('icon_picker_default_tile'),
                    label: 'Стандартная',
                    icon: const Icon(Icons.circle, size: 32),
                    onTap: () => Navigator.of(context).pop(const IconPickResult.reset()),
                  );
                }
                final file = files[index - 1];
                return _Tile(
                  key: Key('icon_picker_tile_${file.fileName}'),
                  label: file.displayName,
                  icon: file.format == IconFileFormat.svg
                      ? const Icon(Icons.image, size: 32)
                      : Image.file(File(file.path), width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                  onTap: () => Navigator.of(context).pop(IconPickResult.file(file.fileName)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(height: 4), Text(label, overflow: TextOverflow.ellipsis)],
      ),
    );
  }
}
```

For an SVG tile, rendering an actual `SvgPicture.file` preview is deliberately skipped here in favor of a placeholder `Icons.image` glyph — the grid is for picking a *file*, not previewing its exact tinted map appearance (that only exists once color is known, computed later in `IconImageCache`); keeping the picker dependency-light (no `flutter_svg` widget import in this file) avoids coupling the picker's test suite to SVG decoding.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/icons/icon_picker_sheet_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the failing tests for the form's icon row**

Add to `app/test/waypoints/waypoint_form_sheet_test.dart` (new `import 'dart:io';`, `import 'package:file/memory.dart';`, `import 'package:app/icons/icon_library_scanner.dart';` at the top, and these cases inside `main()`):

```dart
  testWidgets('picking a raster icon hides the color swatch', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');

    await tester.pumpWidget(_harness(() {}, (_) {}, iconScanner: scanner));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_color_swatch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_color_swatch')), findsNothing);
  });

  testWidgets('picking an svg icon keeps the color swatch visible', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('marker.svg').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');

    await tester.pumpWidget(_harness(() {}, (_) {}, iconScanner: scanner));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_marker.svg')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_color_swatch')), findsOneWidget);
  });

  testWidgets('picking "Стандартная" after a raster pick brings the color swatch back and clears iconFileName', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    WaypointFormResult? result;

    await tester.pumpWidget(_harness(() {}, (r) => result = r, iconScanner: scanner));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_default_tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_color_swatch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result!.iconFileName, isNull);
  });

  testWidgets('submitted result carries the picked icon file name', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('marker.svg').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    WaypointFormResult? result;

    await tester.pumpWidget(_harness(() {}, (r) => result = r, iconScanner: scanner));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_marker.svg')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result!.iconFileName, 'marker.svg');
  });
```

Also update the existing `_harness` helper (near the top of the file) to accept and forward an `iconScanner`:

```dart
Widget _harness(
  VoidCallback onOpen,
  ValueChanged<WaypointFormResult?> onResult, {
  Waypoint? existing,
  IconLibraryScanner? iconScanner,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onOpen();
            final result = await showWaypointFormSheet(context, existing: existing, iconScanner: iconScanner);
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}
```

Every pre-existing call to `showWaypointFormSheet` inside this test file goes through `_harness`, so no other call site needs editing. Every existing `WaypointFormResult(...)` literal in this file (the "returns null when dismissed" test) needs `iconFileName: null` added once that field exists (Step 6) — Dart's required-named-parameter check will flag exactly where.

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/waypoints/waypoint_form_sheet_test.dart`
Expected: FAIL — `showWaypointFormSheet` has no `iconScanner`/`initialIconFileName` parameter yet, `WaypointFormResult` has no `iconFileName` field yet, no `waypoint_icon_button` key exists yet.

- [ ] **Step 7: Wire the icon picker into `waypoint_form_sheet.dart`**

Modify `app/lib/waypoints/waypoint_form_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' hide colorFromHex, colorToHex;

import '../icons/icon_library_scanner.dart';
import '../icons/icon_picker_sheet.dart';
import 'waypoint_color.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';

class WaypointFormResult {
  const WaypointFormResult({
    required this.name,
    required this.type,
    required this.note,
    required this.color,
    required this.iconFileName,
  });

  final String name;
  final String type;
  final String note;
  final String? color;
  final String? iconFileName;
}

Future<WaypointFormResult?> showWaypointFormSheet(
  BuildContext context, {
  Waypoint? existing,
  String? initialIconFileName,
  IconLibraryScanner? iconScanner,
}) {
  return showModalBottomSheet<WaypointFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => WaypointFormSheet(
      existing: existing,
      initialIconFileName: initialIconFileName,
      iconScanner: iconScanner,
    ),
  );
}

class WaypointFormSheet extends StatefulWidget {
  const WaypointFormSheet({super.key, this.existing, this.initialIconFileName, this.iconScanner});

  final Waypoint? existing;
  final String? initialIconFileName;
  final IconLibraryScanner? iconScanner;

  @override
  State<WaypointFormSheet> createState() => _WaypointFormSheetState();
}

class _WaypointFormSheetState extends State<WaypointFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _noteController =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _selectedType = widget.existing?.type ?? defaultWaypointType;
  String? _selectedColor;
  String? _selectedIconFileName;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.existing?.color;
    _selectedIconFileName = widget.initialIconFileName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _effectiveColorHex =>
      _selectedColor ?? waypointTypeColors[_selectedType] ?? waypointTypeColors[defaultWaypointType]!;

  bool get _colorPickerVisible => _selectedIconFileName == null || _selectedIconFileName!.toLowerCase().endsWith('.svg');

  Future<void> _openColorPicker() async {
    Color picked = colorFromHex(_effectiveColorHex);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (color) => picked = color,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('waypoint_color_picker_reset_button'),
            onPressed: () => Navigator.of(dialogContext).pop('reset'),
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('waypoint_color_picker_select_button'),
            onPressed: () => Navigator.of(dialogContext).pop('select'),
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );

    if (action == 'select') {
      setState(() => _selectedColor = colorToHex(picked));
    } else if (action == 'reset') {
      setState(() => _selectedColor = null);
    }
  }

  Future<void> _openIconPicker() async {
    final result = await showIconPickerSheet(context, scanner: widget.iconScanner);
    if (result == null) return;
    setState(() => _selectedIconFileName = result.fileName);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
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
          Text(isEditing ? 'Редактировать метку' : 'Новая метка', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final type in waypointTypes)
                ChoiceChip(
                  key: Key('waypoint_type_chip_$type'),
                  label: Text(waypointTypeLabels[type] ?? type),
                  selected: _selectedType == type,
                  onSelected: (_) => setState(() => _selectedType = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Иконка'),
              const SizedBox(width: 12),
              OutlinedButton(
                key: const Key('waypoint_icon_button'),
                onPressed: _openIconPicker,
                child: Text(_selectedIconFileName ?? 'Стандартная'),
              ),
            ],
          ),
          if (_colorPickerVisible) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Цвет'),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _openColorPicker,
                  child: Container(
                    key: const Key('waypoint_color_swatch'),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorFromHex(_effectiveColorHex),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_note_field'),
            controller: _noteController,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Заметка (необязательно)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('waypoint_save_button'),
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      WaypointFormResult(
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        note: _noteController.text.trim(),
                        color: _selectedColor,
                        iconFileName: _selectedIconFileName,
                      ),
                    ),
            child: Text(isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }
}
```

Then fix the one pre-existing literal construction of `WaypointFormResult` in the test file (the "returns null when dismissed without saving" test) by adding `iconFileName: null` to it.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd app && flutter test test/waypoints/waypoint_form_sheet_test.dart test/icons/icon_picker_sheet_test.dart`
Expected: PASS (all cases, old and new).

- [ ] **Step 9: Run the full suite to catch any other broken call site**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` clean; any remaining compile error will point at a `WaypointFormResult(...)` construction site missing the new required `iconFileName` argument or a `showWaypointFormSheet` caller — fix by passing through (`iconFileName: null` for a still-untouched call site is correct for now; Task 7 wires the real values).

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/icons/icon_picker_sheet.dart lib/waypoints/waypoint_form_sheet.dart test/icons/icon_picker_sheet_test.dart test/waypoints/waypoint_form_sheet_test.dart
git commit -m "feat: add icon picker sheet, wire into the waypoint form"
```

---

## Task 7: Persist the icon choice on create/edit

**Files:**
- Modify: `app/lib/waypoints/waypoints_controller.dart`
- Modify: `app/lib/waypoints/waypoint_actions.dart`
- Modify: `app/lib/waypoints/waypoints_list_screen.dart`
- Test: `app/test/waypoints/waypoints_controller_test.dart` (check if it exists; extend or create)
- Test: `app/test/waypoints/waypoint_actions_test.dart` (check if it exists; extend or create)

**Interfaces:**
- Consumes: `waypointIconAssignmentsControllerProvider` (Task 3).
- Produces: `WaypointsController.createWaypoint(...)` now returns `Future<Waypoint>` (was `Future<void>`) — the server-assigned waypoint, so callers can persist a local icon choice against its real id.

- [ ] **Step 1: Check for existing tests on the touched files**

Run: `cd app && find test/waypoints -iname "*controller*" -o -iname "*actions*"`

If `waypoints_controller_test.dart` or `waypoint_actions_test.dart` exist, read them first and extend in place with the new cases below instead of creating new files (follow whatever fake/harness setup they already use — likely the same `FakeWaypointsRepository` seen in `test/waypoints/fakes.dart`). If neither exists, create them as shown below (this repo's existing coverage for these two files may currently live only inside `map_screen_test.dart`'s "creating a waypoint via the controller..." test — that test still passes unmodified since it never used `createWaypoint`'s return value).

- [ ] **Step 2: Write the failing test for `createWaypoint`'s new return value**

Add (to the existing or new `app/test/waypoints/waypoints_controller_test.dart`):

```dart
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

void main() {
  test('createWaypoint returns the server-created waypoint', () async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final created = Waypoint(
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
    final repo = FakeWaypointsRepository()..createResult = created;
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(waypointsControllerProvider.notifier).createWaypoint(
          ownerId: 'u1',
          name: 'Summit',
          type: 'generic',
          note: '',
          color: null,
          lat: 1.0,
          lng: 2.0,
        );

    expect(result, created);
  });
}
```

(If a `waypoints_controller_test.dart` already exists, add this `test(...)` block inside its existing `main()` instead of the whole file above, keeping its existing imports/overrides pattern.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd app && flutter test test/waypoints/waypoints_controller_test.dart`
Expected: FAIL — `createWaypoint` currently returns `Future<void>`, so `final result = await ...createWaypoint(...)` doesn't type-check against `Waypoint`.

- [ ] **Step 4: Change `createWaypoint` to return the created waypoint**

In `app/lib/waypoints/waypoints_controller.dart`, change the method signature and its body's success path:

```dart
  Future<Waypoint> createWaypoint({
    required String ownerId,
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
    required String? color,
  }) async {
    final token = await _storage.read();
    if (token == null) {
      throw const WaypointException('Не выполнен вход');
    }

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Waypoint(
      id: tempId,
      orgId: '',
      ownerId: ownerId,
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      color: color,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created = await _repository.create(token, name: name, type: type, note: note, color: color, lat: lat, lng: lng);
      state = [for (final w in state) if (w.id == tempId) created else w];
      return created;
    } on WaypointException {
      state = [for (final w in state) if (w.id != tempId) w];
      rethrow;
    }
  }
```

Note the `token == null` branch changes from a silent no-op return to throwing `WaypointException` -- the old code returned `void` with nothing for a caller to act on; now that the return type is `Future<Waypoint>`, that branch must produce a `Waypoint` or throw, and throwing (a state that in practice never happens once logged in, same as every other guard in this file being effectively unreachable in normal operation) is the only correct option that doesn't fabricate a fake waypoint.

- [ ] **Step 5: Run the test to verify it passes, then run the full suite for regressions**

Run: `cd app && flutter test test/waypoints/waypoints_controller_test.dart`
Expected: PASS.

Run: `cd app && flutter analyze && flutter test`
Expected: clean. `map_screen_test.dart`'s existing `createWaypoint` call sites still compile (they never captured/used the return value), but `map_screen.dart`'s own `_createWaypointAtCrosshair` (Step 7 below) needs updating in this same task before this passes fully — do Step 6 first if `flutter analyze` complains there.

- [ ] **Step 6: Write the failing test for icon persistence on edit**

Check whether `app/test/waypoints/waypoint_actions_test.dart` already exists (`find test/waypoints -iname "waypoint_actions_test.dart"`). If yes, read it and add the case below into its existing `main()`/harness; if no, create it following the same fake-provider-override style as `map_screen_test.dart`'s `_baseOverrides`. The test drives `editWaypoint` from inside a real widget (a `Consumer`, so a genuine `WidgetRef` is available — `editWaypoint`'s signature stays `(BuildContext, WidgetRef, Waypoint, {IconLibraryScanner? iconScanner})`), picks an icon through the real picker flow from Task 6, and asserts the pick lands in both the store and the reactive controller:

```dart
import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:app/waypoints/waypoint_actions.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import '../icons/fakes.dart';
import 'fakes.dart';

Waypoint _waypoint() => Waypoint(
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

void main() {
  testWidgets('editing a waypoint and picking an icon persists the assignment', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeWaypointsRepository()..updateResult = _waypoint();
    final iconStore = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(repo),
        waypointIconStoreProvider.overrideWithValue(iconStore),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => editWaypoint(context, ref, _waypoint(), iconScanner: scanner),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(await iconStore.iconFor('w1'), 'camp.png');
    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'camp.png'});
  });
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `cd app && flutter test test/waypoints/waypoint_actions_test.dart`
Expected: FAIL — `editWaypoint` has no `iconScanner` parameter yet, and doesn't call `waypointIconAssignmentsControllerProvider` yet.

- [ ] **Step 8: Wire icon persistence into `waypoint_actions.dart`**

Modify `app/lib/waypoints/waypoint_actions.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';

/// Shows the view/edit/delete bottom sheet for a waypoint. Shared between the
/// map screen (tapping a pin) and the waypoints list screen (tapping a row).
Future<void> showWaypointDetails(BuildContext context, WidgetRef ref, Waypoint waypoint) async {
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

  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    await editWaypoint(context, ref, waypoint);
  } else if (action == 'delete') {
    await deleteWaypoint(context, ref, waypoint);
  }
}

Future<void> editWaypoint(BuildContext context, WidgetRef ref, Waypoint waypoint, {IconLibraryScanner? iconScanner}) async {
  final currentIcon = ref.read(waypointIconAssignmentsControllerProvider)[waypoint.id];
  final result = await showWaypointFormSheet(
    context,
    existing: waypoint,
    initialIconFileName: currentIcon,
    iconScanner: iconScanner,
  );
  if (result == null || !context.mounted) return;
  try {
    await ref.read(waypointsControllerProvider.notifier).updateWaypoint(
          waypoint.id,
          name: result.name,
          type: result.type,
          note: result.note,
          color: result.color,
        );
    await ref.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(waypoint.id, result.iconFileName);
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> deleteWaypoint(BuildContext context, WidgetRef ref, Waypoint waypoint) async {
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
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(waypointsControllerProvider.notifier).deleteWaypoint(waypoint.id);
    await ref.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(waypoint.id, null);
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

(`deleteWaypoint` also clears any local icon assignment for the deleted id, so a future waypoint that happens to reuse... no id reuse actually happens server-side, but leaving a dangling local assignment around forever is simply wasted storage; clearing it is a one-line correctness tidy-up, not scope creep.)

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd app && flutter test test/waypoints/waypoint_actions_test.dart`
Expected: PASS.

- [ ] **Step 10: Wire `WaypointsListScreen` to load assignments on mount**

Modify `app/lib/waypoints/waypoints_list_screen.dart`'s `initState`:

```dart
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(waypointsControllerProvider.notifier).loadWaypoints());
    Future.microtask(() => ref.read(waypointIconAssignmentsControllerProvider.notifier).load());
  }
```

Add `import '../icons/waypoint_icon_assignments_controller.dart';` at the top. This guarantees `editWaypoint`'s `ref.read(waypointIconAssignmentsControllerProvider)[waypoint.id]` pre-fill lookup (Step 8) is populated even when the user reaches the edit sheet via the "Метки" tab without ever having opened the map first.

- [ ] **Step 11: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean except for `map_screen.dart`'s own `_createWaypointAtCrosshair` still calling `createWaypoint` in a way that no longer type-checks cleanly with a discarded return value (it still compiles — `Future<Waypoint>` awaited and ignored is legal — so this should actually already be green; if `flutter analyze` flags an unused-result lint, address it in Task 8 where `_createWaypointAtCrosshair` is edited anyway to capture the id).

- [ ] **Step 12: Commit**

```bash
cd app
git add lib/waypoints/waypoints_controller.dart lib/waypoints/waypoint_actions.dart lib/waypoints/waypoints_list_screen.dart test/waypoints/waypoints_controller_test.dart test/waypoints/waypoint_actions_test.dart
git commit -m "feat: persist local icon choice on waypoint create/edit/delete"
```

---

## Task 8: Map rendering — Symbol path for waypoints with an icon

**Files:**
- Modify: `app/lib/map/map_screen.dart`
- Test: `app/test/map/map_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `waypointIconAssignmentsControllerProvider` (Task 3), `IconImageCache`/`AddImageFn` (Task 5), `IconLibraryScanner`/`IconFile` (Task 1), `renderIconBytes` (Task 4).
- Produces: pure `WaypointRenderMode renderModeForWaypoint(String? iconFileName)` (top-level, next to `circleOptionsForWaypoint`); `_syncSymbols` wired alongside `_syncCircles` in `_runSync`; waypoints with an assigned icon render as `Symbol`s and are excluded from `_syncCircles`.

- [ ] **Step 1: Write the failing test for the pure partition function**

Add to `app/test/map/map_screen_test.dart`, inside the existing `group('circleOptionsForWaypoint', ...)` sibling area (a new top-level `group`):

```dart
  group('renderModeForWaypoint', () {
    test('no assigned icon -> circle', () {
      expect(renderModeForWaypoint(null), WaypointRenderMode.circle);
    });

    test('an assigned icon -> symbol', () {
      expect(renderModeForWaypoint('camp.png'), WaypointRenderMode.symbol);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/map/map_screen_test.dart`
Expected: FAIL — `renderModeForWaypoint`/`WaypointRenderMode` don't exist yet.

- [ ] **Step 3: Add the pure partition function and imports**

In `app/lib/map/map_screen.dart`, add near the top (right after `circleOptionsForWaypoint`):

```dart
enum WaypointRenderMode { circle, symbol }

/// Pure routing decision: a waypoint with a locally-assigned icon renders as
/// an image Symbol; everything else keeps the existing colored Circle.
/// Extracted as a top-level function for the same reason
/// [circleOptionsForWaypoint] is -- unit-testable without a platform view.
WaypointRenderMode renderModeForWaypoint(String? assignedIconFileName) =>
    assignedIconFileName == null ? WaypointRenderMode.circle : WaypointRenderMode.symbol;
```

Add these imports at the top of the file:

```dart
import '../icons/icon_image_cache.dart';
import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/map/map_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Add Symbol-tracking state and the icon cache to `_MapScreenState`**

In `app/lib/map/map_screen.dart`, inside `_MapScreenState`, add alongside the existing circle-tracking fields:

```dart
  final Map<String, Symbol> _symbolsByWaypointId = {};
  final Map<String, String> _appliedSymbolKeys = {};
  late final IconImageCache _iconImageCache = IconImageCache(
    addImage: (name, bytes) async {
      final controller = _controller;
      if (controller == null) return;
      await controller.addImage(name, bytes);
    },
  );
  final IconLibraryScanner _iconLibraryScanner = IconLibraryScanner();
  // Cached per-scan-session so _syncSymbols (which can run many times per
  // second while a track is recording, same as _syncCircles) doesn't rescan
  // the device folder on every tick -- refreshed only when a waypoint's
  // resolved IconFile is actually needed and not yet in this map.
  final Map<String, IconFile> _iconFilesByFileName = {};
  bool _iconFilesLoaded = false;
```

- [ ] **Step 6: Load the icon file listing and icon assignments alongside waypoints**

In `_MapScreenState.initState()`, add:

```dart
    Future.microtask(() {
      if (!mounted) return;
      ref.read(waypointIconAssignmentsControllerProvider.notifier).load();
    });
```

right after the existing `loadWaypoints()` microtask.

- [ ] **Step 7: Clear icon-related caches on style reload**

In `_onStyleLoaded()`, add:

```dart
    _symbolsByWaypointId.clear();
    _appliedSymbolKeys.clear();
    _iconImageCache.clear();
```

right after the existing `_appliedLineKeys.clear();` line (registered images, like circles/lines, don't survive a style reload).

- [ ] **Step 8: Implement `_syncSymbols` and wire it into `_runSync`**

Add this method to `_MapScreenState`, after `_syncCircles`:

```dart
  Future<void> _syncSymbols(List<Waypoint> waypoints, Map<String, String> iconAssignments) async {
    final controller = _controller;
    if (controller == null || controller.symbolManager == null) return;

    final liveSymbolIds = controller.symbols.map((s) => s.id).toSet();
    _symbolsByWaypointId.removeWhere((id, symbol) {
      final stale = !liveSymbolIds.contains(symbol.id);
      if (stale) _appliedSymbolKeys.remove(id);
      return stale;
    });

    final withIcon = waypoints.where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.symbol);
    final currentIds = withIcon.map((w) => w.id).toSet();
    for (final id in _symbolsByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeSymbol(_symbolsByWaypointId.remove(id)!);
        _appliedSymbolKeys.remove(id);
      }
    }

    for (final waypoint in withIcon) {
      final fileName = iconAssignments[waypoint.id]!;
      final colorHex = waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!;
      final key = '$fileName|$colorHex';
      final existing = _symbolsByWaypointId[waypoint.id];
      if (existing != null && _appliedSymbolKeys[waypoint.id] == key) continue;

      final iconFile = await _resolveIconFile(fileName);
      if (iconFile == null) continue; // file was deleted from the device -- leave rendering as-is until next sync picks up a cleared assignment
      final imageName = await _iconImageCache.resolve(iconFile, colorHex);
      final options = SymbolOptions(
        geometry: LatLng(waypoint.lat, waypoint.lng),
        iconImage: imageName,
        iconSize: 1,
      );
      if (existing == null) {
        _symbolsByWaypointId[waypoint.id] = await controller.addSymbol(options, {'waypointId': waypoint.id});
      } else {
        await controller.updateSymbol(existing, options);
      }
      _appliedSymbolKeys[waypoint.id] = key;
    }
  }

  Future<IconFile?> _resolveIconFile(String fileName) async {
    if (!_iconFilesLoaded) {
      final files = await _iconLibraryScanner.scan();
      _iconFilesByFileName
        ..clear()
        ..addEntries(files.map((f) => MapEntry(f.fileName, f)));
      _iconFilesLoaded = true;
    }
    return _iconFilesByFileName[fileName];
  }
```

Update `_syncCircles` so it skips waypoints that are now rendered as symbols — change the loop's filtering. Replace the `for (final waypoint in waypoints)` loop's start with a guard, and replace the stale-removal `currentIds` computation to only count circle-mode waypoints:

```dart
  Future<void> _syncCircles(List<Waypoint> waypoints, Map<String, String> iconAssignments) async {
    final controller = _controller;
    if (controller == null || controller.circleManager == null) return;
    final liveCircleIds = controller.circles.map((c) => c.id).toSet();
    _circlesByWaypointId.removeWhere((id, circle) {
      final stale = !liveCircleIds.contains(circle.id);
      if (stale) _appliedCircleKeys.remove(id);
      return stale;
    });
    final currentUserId = _currentUserId();

    final circleModeWaypoints =
        waypoints.where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.circle).toList();
    final currentIds = circleModeWaypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
        _appliedCircleKeys.remove(id);
      }
    }

    for (final waypoint in circleModeWaypoints) {
      final isOwn = waypoint.ownerId == currentUserId;
      final key = '${waypoint.type}|$isOwn|${waypoint.color ?? ''}';
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        final options = circleOptionsForWaypoint(waypoint, currentUserId);
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
        _appliedCircleKeys[waypoint.id] = key;
      } else if (_appliedCircleKeys[waypoint.id] != key) {
        await controller.updateCircle(existing, circleOptionsForWaypoint(waypoint, currentUserId));
        _appliedCircleKeys[waypoint.id] = key;
      }
    }
  }
```

(A waypoint moving from circle-mode to symbol-mode, or back, now correctly falls into the "not in currentIds anymore" branch of whichever manager it left, and gets freshly added by the other on the same sync pass — no special-cased transition code needed.)

Update `_runSync` to read the icon assignments once and pass them to both:

```dart
  Future<void> _runSync() async {
    _isSyncing = true;
    try {
      final iconAssignments = ref.read(waypointIconAssignmentsControllerProvider);
      final waypoints = ref.read(waypointsControllerProvider);
      await _syncCircles(waypoints, iconAssignments);
      await _syncSymbols(waypoints, iconAssignments);
      await _syncLines();
      await _syncMyLocationCircle();
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
    if (_syncPending) {
      _syncPending = false;
      _requestSync();
    }
  }
```

- [ ] **Step 9: Listen for icon-assignment changes and route symbol taps**

In `build()`, add another `ref.listen`:

```dart
    ref.listen<Map<String, String>>(waypointIconAssignmentsControllerProvider, (previous, next) {
      _requestSync();
    });
```

alongside the existing three `ref.listen` calls.

In `_onMapCreated`, register a symbol-tap handler alongside the existing circle one:

```dart
  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
  }
```

Add the handler, right after `_onCircleTapped`:

```dart
  void _onSymbolTapped(Symbol symbol) {
    final waypointId = symbol.data?['waypointId'] as String?;
    if (waypointId == null) return;
    final waypoints = ref.read(waypointsControllerProvider);
    final index = waypoints.indexWhere((w) => w.id == waypointId);
    if (index == -1) return;
    showWaypointDetails(context, ref, waypoints[index]);
  }
```

- [ ] **Step 10: Persist the icon choice for a newly-created waypoint**

In `_createWaypointAtCrosshair`, capture the created waypoint's id and persist the pick:

```dart
  Future<void> _createWaypointAtCrosshair() async {
    final controller = _controller;
    final cameraPosition = controller?.cameraPosition;
    if (controller == null || cameraPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Карта ещё не готова')),
      );
      return;
    }
    final coordinates = cameraPosition.target;
    final result = await showWaypointFormSheet(context, iconScanner: _iconLibraryScanner);
    if (result == null || !mounted) return;
    try {
      final created = await ref.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: _currentUserId(),
            name: result.name,
            type: result.type,
            note: result.note,
            color: result.color,
            lat: coordinates.latitude,
            lng: coordinates.longitude,
          );
      await ref.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(created.id, result.iconFileName);
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
```

- [ ] **Step 11: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` clean; full `flutter test` suite green. No test exercises `_syncSymbols`/`_syncCircles`'s manager-dependent bodies directly (same pre-existing limitation as `_syncCircles` today — `MapLibreMap` has no platform view under `flutter test`, so `controller`/`symbolManager` stay null and both methods return at their first guard); the added `renderModeForWaypoint` unit tests plus the existing widget tests (which exercise everything up to and including the guarded-return sync calls, proving no exception is thrown) are the coverage this task adds, consistent with the existing precedent documented in this file's own comments about manual device verification.

- [ ] **Step 12: Manual device verification**

Per this repo's established precedent for anything a `flutter test` widget test structurally cannot reach (no real `MapLibreMapController`), verify by hand on a real device/emulator:
1. Drop a PNG and an SVG file into `Android/data/<applicationId>/files/mediafile/iconTypes/` via a file manager (or `adb push`).
2. Create a waypoint, open the icon picker, confirm both files appear with extension-less labels.
3. Pick the SVG icon, pick a custom color, save — confirm the marker on the map shows the tinted SVG image, not a colored circle.
4. Pick the PNG icon — confirm the color row disappears from the form, and the marker shows the raw image, untinted.
5. Edit the same waypoint, switch back to "Стандартная" — confirm the marker reverts to a colored circle.
6. Restart the app — confirm the icon choice survives (read back from `flutter_secure_storage`).
7. Delete the icon file from the device folder via a file manager, then reopen the map — confirm the marker falls back gracefully (stays as whatever it last rendered, per Step 8's `_resolveIconFile` returning null; no crash).

- [ ] **Step 13: Commit**

```bash
cd app
git add lib/map/map_screen.dart test/map/map_screen_test.dart
git commit -m "feat: render waypoints with a locally-assigned icon as image Symbols"
```

---

## Final Verification

- [ ] Run `cd app && flutter analyze` — must be clean.
- [ ] Run `cd app && flutter test` — full suite green.
- [ ] Confirm no files under `api/` were touched (`git diff --stat main -- api/` should be empty) — this feature is frontend-only per the spec.
- [ ] Manual device verification from Task 8, Step 12, completed and confirmed working.
