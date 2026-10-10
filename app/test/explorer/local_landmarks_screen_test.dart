import 'dart:io';

import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/map/screens/available_maps/maps_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'explorer_test_harness.dart';

void main() {
  late ExplorerHarness h;

  /// Подзаголовок шапки (текущая папка).
  String? subtitle(WidgetTester tester) => tester.widget<MapsAppBar>(find.byType(MapsAppBar)).subtitle;

  Future<void> addWaypoint(String name, {String? folder}) => h.f.services.creation.create(
    MarkerDraft(type: LandmarkType.waypoint, longitude: 30, latitude: 50, name: name, targetFolder: folder),
  );

  testWidgets('opens the landmarks folder at start, with folders and files', (tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() => addWaypoint('Bunker', folder: h.f.paths.landmarks));
    await h.pumpApp(tester);

    expect(h.f.services.explorerController.state.currentFolder, h.f.paths.landmarks);
    expect(find.text('Локальные метки'), findsOneWidget);
    expect(subtitle(tester), 'Мои метки');
    expect(find.byKey(const Key('explorer_storage')), findsOneWidget);
    expect(find.text('1 файл. · 2 папки'), findsOneWidget);
    expect(find.byKey(const Key('folder_row_Несортированные метки')), findsOneWidget);
    expect(find.byKey(const Key('item_row_Bunker')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('shows the loader until the folder is read', (tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(h.app());
      await tester.pump();
    });
    expect(find.byKey(const Key('explorer_loading')), findsOneWidget);
    await h.settle(tester);
    expect(find.byKey(const Key('explorer_loading')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('an empty folder shows «Папка пуста»', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester, initialFolder: h.f.paths.recordedTracks);
    expect(find.byKey(const Key('explorer_empty')), findsOneWidget);
    expect(find.text('Папка пуста'), findsOneWidget);
    expect(subtitle(tester), 'Мои метки / Записанные треки');
    await h.dispose(tester);
  });

  testWidgets('an error is shown in a SnackBar', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester, initialFolder: p.join(h.f.paths.landmarks, 'missing'));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('does not exist'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('tapping a folder opens it; back goes up', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await h.tap(tester, find.byKey(const Key('folder_row_Несортированные метки')));
    expect(h.f.services.explorerController.state.currentFolder, h.f.paths.importDefault);
    await tester.runAsync(() => tester.binding.handlePopRoute());
    await h.settle(tester);
    expect(h.f.services.explorerController.state.currentFolder, h.f.paths.landmarks);
    await h.dispose(tester);
  });

  testWidgets('long press selects; delete removes the file after confirmation', (tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() => addWaypoint('Bunker', folder: h.f.paths.landmarks));
    await h.pumpApp(tester);
    final file = h.f.services.explorerController.allItems.single.path;

    await tester.longPress(find.byKey(const Key('item_row_Bunker')));
    await tester.pump();
    expect(find.byKey(const Key('explorer_selection_bar')), findsOneWidget);
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection_delete')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('confirm_dialog_ok')));
    expect(await tester.runAsync(() => File(file).exists()), isFalse);
    expect(find.byKey(const Key('item_row_Bunker')), findsNothing);
    expect(find.byKey(const Key('explorer_selection_bar')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('«+» → «Новая папка» creates a folder here', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await h.tap(tester, find.byKey(const Key('explorer_fab')));
    await tester.pumpAndSettle();
    expect(find.text('Папки и файлы'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('marker_type_route')), findsOneWidget);
    await tester.tap(find.byKey(const Key('marker_type_folder')));
    await h.settle(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new_folder_name')), 'Поход');
    await h.tap(tester, find.byKey(const Key('new_folder_ok')));
    expect(await tester.runAsync(() => Directory(p.join(h.f.paths.landmarks, 'Поход')).exists()), isTrue);
    expect(find.byKey(const Key('folder_row_Поход')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('the overflow menu has sort, filter, statistics, select all', (tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async {
      await addWaypoint('A', folder: h.f.paths.landmarks);
      await addWaypoint('B', folder: h.f.paths.landmarks);
    });
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('maps_more_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explorer_menu_selectAll')));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('selection_cancel')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('maps_more_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explorer_menu_statistics')));
    await tester.pumpAndSettle();
    expect(find.text('Файлов: 2'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«+» → «Файл меток» creates an .ldk file here', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await h.tap(tester, find.byKey(const Key('explorer_fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marker_type_landmark_file')));
    await h.settle(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ldk_create_name')), 'Посты');
    await h.tap(tester, find.byKey(const Key('ldk_create_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_section')), findsOneWidget);
    expect(find.text('Посты'), findsOneWidget);
    final files = await tester.runAsync(() => h.f.services.repository.listIn(h.f.paths.landmarks));
    expect(files!.single, endsWith('.ldk'));
    await h.dispose(tester);
  });

  testWidgets('«+» → an unsupported kind explains itself', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await h.tap(tester, find.byKey(const Key('explorer_fab')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('marker_type_text')),
      200,
      scrollable: find.descendant(of: find.byKey(const Key('explorer_create_sheet')), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.byKey(const Key('marker_type_text')));
    await h.settle(tester);
    expect(find.textContaining('«Текст» пока нельзя создать'), findsOneWidget);
    await h.dispose(tester);
  });
}
