import 'dart:io';

import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/clipboard/landmarks_clipboard.dart';
import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/explorer/operations/explorer_operations.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../explorer_fixture.dart';

void main() {
  late ExplorerFixture f;
  late LandmarksClipboard clipboard;
  late DisplayRegistry display;
  late ExplorerOperations ops;
  late String target;

  setUp(() async {
    f = await ExplorerFixture.create();
    clipboard = LandmarksClipboard();
    display = DisplayRegistry();
    ops = ExplorerOperations(
      repository: f.repository,
      reader: f.reader,
      storage: f.storage,
      clipboard: clipboard,
      display: display,
    );
    target = p.join(f.paths.landmarks, 'target');
  });
  tearDown(() => f.dispose());

  test('deleteOne removes the file and takes it off the map', () async {
    final path = await f.waypoint('A');
    display.display(path);
    final result = await ops.deleteOne(path);
    expect(result.success, isTrue);
    expect(result.affectedCount, 1);
    expect(File(path).existsSync(), isFalse);
    expect(display.isDisplayed(path), isFalse);
  });

  test('deleteSelected goes on after an error', () async {
    final a = await f.waypoint('A');
    final b = await f.waypoint('B');
    final missing = p.join(f.paths.landmarks, 'missing.wpt');
    final result = await ops.deleteSelected({a, missing, b});
    expect(result.success, isFalse);
    expect(result.affectedCount, 2);
    expect(result.errorMessage, contains('missing.wpt'));
    expect(File(a).existsSync() || File(b).existsSync(), isFalse);
  });

  test('display and undisplay touch only the registry', () async {
    final a = await f.waypoint('A');
    expect((await ops.displaySelected({a, '/x'})).affectedCount, 2);
    expect(display.count, 2);
    await ops.undisplaySelected({a});
    expect(display.isDisplayed(a), isFalse);
    expect(File(a).existsSync(), isTrue);
  });

  test('copy + pasteAll creates copies in the target, keeps the sources', () async {
    final a = await f.waypoint('A');
    final b = await f.track('B');
    expect((await ops.copySelected({a, b})).affectedCount, 2);
    expect(clipboard.isCut, isFalse);
    expect(clipboard.entries.map((e) => e.originalName), unorderedEquals(['A', 'B']));

    final result = await ops.pasteAll(target);
    expect(result.success, isTrue);
    expect(result.affectedCount, 2);
    expect(File(a).existsSync(), isTrue);
    expect(File(p.join(target, p.basename(a))).readAsBytesSync(), File(a).readAsBytesSync());
    expect(File(p.join(target, p.basename(b))).existsSync(), isTrue);
    expect(clipboard.entries, hasLength(2));
  });

  test('cut + pasteAll moves, the source disappears, display follows', () async {
    final a = await f.waypoint('A');
    display.display(a);
    await ops.cutSelected({a});
    expect(clipboard.isCut, isTrue);
    final result = await ops.pasteAll(target);
    expect(result.affectedCount, 1);
    final moved = p.join(target, p.basename(a));
    expect(File(a).existsSync(), isFalse);
    expect(File(moved).existsSync(), isTrue);
    expect(clipboard.isEmpty, isTrue);
    expect(display.isDisplayed(moved), isTrue);
    expect(display.isDisplayed(a), isFalse);
  });

  test('pasting over taken names adds _1, _2', () async {
    final a = await f.waypoint('A');
    await ops.copySelected({a});
    await ops.pasteAll(target);
    await ops.pasteAll(target);
    await ops.pasteAll(target);
    final stem = p.basenameWithoutExtension(a);
    expect(
      Directory(target).listSync().map((e) => p.basename(e.path)),
      unorderedEquals(['$stem.wpt', '${stem}_1.wpt', '${stem}_2.wpt']),
    );
  });

  test('cut into the same folder leaves the file in place', () async {
    final a = await f.waypoint('A');
    await ops.cutSelected({a});
    final result = await ops.pasteAll(p.dirname(a));
    expect(result.affectedCount, 1);
    expect(File(a).existsSync(), isTrue);
    expect(Directory(p.dirname(a)).listSync().whereType<File>(), hasLength(1));
  });

  test('pasteOne pastes a single entry', () async {
    final a = await f.waypoint('A');
    final b = await f.waypoint('B');
    await ops.cutSelected({a, b});
    final result = await ops.pasteOne(target, b);
    expect(result.affectedCount, 1);
    expect(File(b).existsSync(), isFalse);
    expect(File(a).existsSync(), isTrue);
    expect(clipboard.entries.single.sourcePath, a);
    expect((await ops.pasteOne(target, '/not/in/clipboard.wpt')).success, isFalse);
  });

  test('a source that vanished before paste is an error, others go on', () async {
    final a = await f.waypoint('A');
    final b = await f.waypoint('B');
    await ops.copySelected({a, b});
    File(a).deleteSync();
    final result = await ops.pasteAll(target);
    expect(result.success, isFalse);
    expect(result.affectedCount, 1);
  });

  test('unreadable files do not get into the clipboard', () async {
    final bad = p.join(f.paths.landmarks, 'bad.wpt');
    File(bad).writeAsBytesSync([1, 2, 3]);
    final result = await ops.copySelected({bad});
    expect(result.success, isFalse);
    expect(clipboard.isEmpty, isTrue);
  });

  test('editDetailsSelected sets name and colour on every file', () async {
    final a = await f.waypoint('A', color: 0xFF000000);
    final t = await f.track('T');
    final result = await ops.editDetailsSelected(
      {a, t},
      const MetadataPatch(set: {'name': 'Renamed', 'color': 0xFF123456}),
    );
    expect(result.success, isTrue);
    expect(result.affectedCount, 2);
    for (final path in [a, t]) {
      final meta = (await f.repository.load(path)).content.userMetadata;
      expect(meta.name, 'Renamed');
      expect(meta.colorValue, 0xFF123456);
      expect(meta.version, 1);
    }
    final track = (await f.repository.load(t)).content as TrackObject;
    expect(track.segments.single.locations, hasLength(2));
  });

  test('editDetailsSelected refuses keys beyond name, colour and icon', () async {
    final a = await f.waypoint('A');
    final result = await ops.editDetailsSelected({a}, const MetadataPatch(set: {'description': 'x'}));
    expect(result.success, isFalse);
    expect(result.errorMessage, contains('description'));
    expect((await f.repository.load(a)).content.userMetadata.version, 0);
  });
}
