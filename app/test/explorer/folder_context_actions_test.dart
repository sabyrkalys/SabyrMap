import 'dart:io';

import 'package:app/exceptions/folder_exception.dart';
import 'package:app/explorer/folder_context_actions.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  late String trip;
  setUp(() async {
    f = await ServicesFixture.create();
    trip = p.join(f.paths.landmarks, 'Поход');
    Directory(p.join(trip, 'День 1')).createSync(recursive: true);
    await f.services.creation.create(
      MarkerDraft(type: LandmarkType.waypoint, longitude: 30, latitude: 50, name: 'Привал', targetFolder: trip),
    );
  });
  tearDown(() => f.dispose());

  ExplorerFolderNode node(String path) => ExplorerFolderNode(path: path, name: p.basename(path));

  test('deleteRecursive removes the folder and everything in it', () async {
    await f.services.folders.deleteRecursive(trip);
    expect(Directory(trip).existsSync(), isFalse);
  });

  test('rename moves the folder with its content', () async {
    final to = p.join(f.paths.landmarks, 'Поход 2026');
    await f.services.folders.rename(trip, to);
    expect(Directory(trip).existsSync(), isFalse);
    expect(Directory(p.join(to, 'День 1')).existsSync(), isTrue);
    expect(Directory(to).listSync().whereType<File>(), hasLength(1));
  });

  test('rename onto an existing folder or into itself throws', () async {
    Directory(p.join(f.paths.landmarks, 'Занято')).createSync();
    expect(
      () => f.services.folders.rename(trip, p.join(f.paths.landmarks, 'Занято')),
      throwsA(isA<FolderException>().having((e) => e.message, 'message', 'уже существует')),
    );
    expect(() => f.services.folders.rename(trip, p.join(trip, 'День 1', 'x')), throwsA(isA<FolderException>()));
    expect(() => f.services.folders.rename(trip, p.join(f.root.path, 'outside')), throwsA(isA<FolderException>()));
  });

  test('isDescendant', () {
    final folders = f.services.folders;
    expect(folders.isDescendant(f.paths.landmarks, trip), isTrue);
    expect(folders.isDescendant(trip, p.join(trip, 'День 1')), isTrue);
    expect(folders.isDescendant(trip, trip), isFalse);
    expect(folders.isDescendant(p.join(trip, 'День 1'), trip), isFalse);
  });

  test('the root, its parents and the built-in folders are protected', () async {
    final folders = f.services.folders;
    for (final path in [f.paths.landmarks, f.paths.appRoot, '/', f.paths.importDefault, f.paths.recordedTracks]) {
      expect(folders.isEditable(path), isFalse, reason: path);
      await expectLater(folders.deleteRecursive(path), throwsA(isA<FolderException>()), reason: path);
    }
    expect(Directory(f.paths.landmarks).existsSync(), isTrue);
    expect(folders.isEditable(trip), isTrue);
  });

  test('createSubfolder and details', () async {
    final made = await f.services.folders.createSubfolder(trip, ' День 2 ');
    expect(p.basename(made), 'День 2');
    expect(() => f.services.folders.createSubfolder(trip, 'День 2'), throwsA(isA<FolderException>()));
    expect(() => f.services.folders.createSubfolder(trip, 'a/b'), throwsA(isA<FolderException>()));
    final details = await f.services.folders.details(trip);
    expect((details.folderCount, details.fileCount), (2, 1));
    expect(details.totalBytes, greaterThan(0));
    expect(details.lastModifiedMs, greaterThan(0));
  });

  test('actions: bookmark, copy, cut, rename and delete report what happened', () async {
    final s = f.services;
    expect(await FolderContextActions.bookmark(s, node(trip)), 'Добавлено в закладки');
    await FolderContextActions.bookmark(s, node(trip));
    expect(FolderContextActions.bookmarks(s), [trip]);

    expect(FolderContextActions.copy(s, node(trip)), 'Скопировано: Поход');
    expect(s.explorerController.clipboard.entries.single.isFolder, isTrue);
    expect(s.explorerController.clipboard.isCut, isFalse);
    expect(FolderContextActions.cut(s, node(trip)), 'Вырезано: Поход');
    expect(s.explorerController.clipboard.isCut, isTrue);
    expect(FolderContextActions.cut(s, node(f.paths.importDefault)), FolderContextActions.unavailable);
    expect(FolderContextActions.copy(s, node(f.paths.landmarks)), FolderContextActions.unavailable);

    expect(await FolderContextActions.rename(s, node(trip), 'Поход'), isNull);
    expect(await FolderContextActions.rename(s, node(trip), 'Озеро'), 'Папка переименована');
    final lake = p.join(f.paths.landmarks, 'Озеро');
    expect(await FolderContextActions.rename(s, node(f.paths.recordedTracks), 'X'), FolderContextActions.unavailable);
    expect(await FolderContextActions.delete(s, node(lake)), 'Папка удалена');
    expect(Directory(lake).existsSync(), isFalse);
  });

  group('pasting folders', () {
    test('a copied folder is copied with its content; a taken name gets _1', () async {
      final s = f.services;
      FolderContextActions.copy(s, node(trip));
      final target = p.join(f.paths.landmarks, 'Архив');
      Directory(target).createSync();
      expect((await s.explorerOperations.pasteAll(target)).affectedCount, 1);
      expect((await s.explorerOperations.pasteAll(target)).affectedCount, 1);
      expect(Directory(p.join(target, 'Поход', 'День 1')).existsSync(), isTrue);
      expect(Directory(p.join(target, 'Поход_1')).existsSync(), isTrue);
      expect(Directory(trip).existsSync(), isTrue);
    });

    test('a cut folder moves and leaves the clipboard', () async {
      final s = f.services;
      FolderContextActions.cut(s, node(trip));
      final result = await s.explorerOperations.pasteAll(f.paths.importDefault);
      expect(result.success, isTrue);
      expect(Directory(trip).existsSync(), isFalse);
      expect(Directory(p.join(f.paths.importDefault, 'Поход', 'День 1')).existsSync(), isTrue);
      expect(s.explorerController.clipboard.isEmpty, isTrue);
    });

    test('a folder cannot be pasted into itself', () async {
      final s = f.services;
      FolderContextActions.cut(s, node(trip));
      final result = await s.explorerOperations.pasteAll(p.join(trip, 'День 1'));
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('саму себя'));
      expect(Directory(trip).existsSync(), isTrue);
    });
  });
}
