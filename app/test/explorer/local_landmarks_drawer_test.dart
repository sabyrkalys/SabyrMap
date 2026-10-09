import 'dart:io';

import 'package:app/explorer/folder_context_actions.dart';
import 'package:app/explorer/local_landmarks_drawer.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:app/map/screens/available_maps/maps_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'explorer_test_harness.dart';

void main() {
  testWidgets('every place is listed; the device shows its size and meter', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drawer_place_landmarks')), findsOneWidget);
    expect(find.text('Мои загрузки'), findsOneWidget);
    expect(find.text('Память устройства (487 ГБ)'), findsOneWidget);
    expect(find.text('ЛОКАЛЬНЫЕ МЕТКИ'), findsOneWidget);
    expect(find.byKey(const Key('drawer_device_storage')), findsOneWidget);
    expect(find.text('ОНЛАЙН-МЕТКИ'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('tapping a place opens it', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('drawer_place_device')));

    final state = h.f.services.explorerController.state;
    expect(state.currentPlace!.kind, PlaceRootKind.deviceFolder);
    expect(state.currentFolder, h.device);
    expect(find.byKey(const Key('folder_row_DCIM')), findsOneWidget);
    expect(tester.widget<MapsAppBar>(find.byType(MapsAppBar)).subtitle, 'Память устройства (487 ГБ)');

    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_device_storage')), findsOneWidget);
    expect(find.text('239 ГБ / 487 ГБ'), findsWidgets);
    await h.dispose(tester);
  });

  testWidgets('online marks show «Раздел в разработке»', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online_my_marks')));
    await tester.pump();
    expect(find.text('Раздел в разработке'), findsOneWidget);
    await h.dispose(tester);
  });

  test('the device title carries the volume size only for the device place', () {
    const device = PlaceRoot(id: 'device', title: 'Память устройства', path: '/s', kind: PlaceRootKind.deviceFolder);
    const marks = PlaceRoot(id: 'landmarks', title: 'Мои метки', path: '/l', kind: PlaceRootKind.landmarks);
    expect(LocalLandmarksDrawer.titleOf(device, null), 'Память устройства');
    expect(LocalLandmarksDrawer.titleOf(marks, null), 'Мои метки');
  });

  group('bookmarks', () {
    Future<(ExplorerHarness, String)> withBookmark(WidgetTester tester) async {
      final h = await ExplorerHarness.create(tester);
      final trip = p.join(h.f.paths.landmarks, 'Поход');
      await tester.runAsync(() async {
        await Directory(trip).create();
        await FolderContextActions.bookmark(h.f.services, ExplorerFolderNode(path: trip, name: 'Поход'));
      });
      await h.pumpApp(tester);
      await tester.tap(find.byKey(const Key('maps_menu_button')));
      await tester.pumpAndSettle();
      return (h, trip);
    }

    testWidgets('a bookmarked folder is listed above «ЛОКАЛЬНЫЕ МЕТКИ»', (tester) async {
      final (h, _) = await withBookmark(tester);
      expect(find.text('ЗАКЛАДКИ'), findsOneWidget);
      expect(find.byKey(const Key('drawer_bookmark_Поход')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ЗАКЛАДКИ')).dy,
        lessThan(tester.getTopLeft(find.text('ЛОКАЛЬНЫЕ МЕТКИ')).dy),
      );
      await h.dispose(tester);
    });

    testWidgets('a tap opens the folder', (tester) async {
      final (h, trip) = await withBookmark(tester);
      await h.tap(tester, find.byKey(const Key('drawer_bookmark_Поход')));
      expect(h.f.services.explorerController.state.currentFolder, trip);
      expect(h.f.services.explorerController.state.currentPlace!.kind, PlaceRootKind.landmarks);
      await h.dispose(tester);
    });

    testWidgets('a long press offers to remove it; ОТМЕНА keeps it', (tester) async {
      final (h, trip) = await withBookmark(tester);
      await tester.longPress(find.byKey(const Key('drawer_bookmark_Поход')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bookmark_menu')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bookmark_menu_cancel')));
      await tester.pumpAndSettle();
      expect(FolderContextActions.bookmarks(h.f.services), [trip]);

      await tester.longPress(find.byKey(const Key('drawer_bookmark_Поход')));
      await tester.pumpAndSettle();
      await h.tap(tester, find.byKey(const Key('bookmark_menu_remove')));
      expect(FolderContextActions.bookmarks(h.f.services), isEmpty);
      expect(find.text('ЗАКЛАДКИ'), findsNothing);
      await h.dispose(tester);
    });
  });
}
