import 'dart:io';

import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../explorer/explorer_test_harness.dart';

void main() {
  Future<ExplorerHarness> openDrawer(WidgetTester tester, {List<String> folders = const []}) async {
    final h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async {
      for (final name in folders) {
        final path = p.join(h.f.paths.landmarks, name);
        await Directory(path).create();
        await h.f.services.bookmarkController.addFromFolder(path);
      }
    });
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('no bookmarks → no section at all', (tester) async {
    final h = await openDrawer(tester);
    expect(find.text('ЗАКЛАДКИ'), findsNothing);
    expect(find.byKey(const Key('bookmarks_section')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('one bookmark → the section with one tile, above «ЛОКАЛЬНЫЕ МЕТКИ»', (tester) async {
    final h = await openDrawer(tester, folders: ['Поход']);
    expect(find.byKey(const Key('bookmarks_section')), findsOneWidget);
    expect(find.byKey(const Key('bookmark_tile_Поход')), findsOneWidget);
    expect(tester.getTopLeft(find.text('ЗАКЛАДКИ')).dy, lessThan(tester.getTopLeft(find.text('ЛОКАЛЬНЫЕ МЕТКИ')).dy));
    await h.dispose(tester);
  });

  testWidgets('several bookmarks keep their order', (tester) async {
    final h = await openDrawer(tester, folders: ['Озеро', 'Поход', 'Архив']);
    final ys = [
      for (final n in ['Озеро', 'Поход', 'Архив']) tester.getTopLeft(find.byKey(Key('bookmark_tile_$n'))).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
    await h.dispose(tester);
  });

  testWidgets('a tap opens the folder and closes the panel', (tester) async {
    final h = await openDrawer(tester, folders: ['Поход']);
    await h.tap(tester, find.byKey(const Key('bookmark_tile_Поход')));
    expect(h.f.services.explorerController.state.currentFolder, p.join(h.f.paths.landmarks, 'Поход'));
    await h.dispose(tester);
  });

  testWidgets('long press → menu; deleting the last bookmark hides the section', (tester) async {
    final h = await openDrawer(tester, folders: ['Поход']);
    await tester.longPress(find.byKey(const Key('bookmark_tile_Поход')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmark_menu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bookmark_menu_remove')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('bookmark_delete_yes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmarks_section')), findsNothing);
    expect(find.text('ЗАКЛАДКИ'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('long press on a place → «Добавить в закладки» with the place title', (tester) async {
    final h = await openDrawer(tester);
    await tester.longPress(find.byKey(const Key('drawer_place_landmarks')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('place_menu_bookmark')));
    await tester.pumpAndSettle();
    final b = h.f.services.bookmarkController.bookmarks.single;
    expect((b.name, b.path), ('Мои метки', h.f.paths.landmarks));
    expect(find.byKey(const Key('bookmark_tile_Мои метки')), findsOneWidget);
    expect(PlaceRootKind.landmarks.name, 'landmarks');
    await h.dispose(tester);
  });
}
