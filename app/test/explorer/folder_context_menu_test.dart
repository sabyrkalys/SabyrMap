import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'explorer_test_harness.dart';

void main() {
  late ExplorerHarness h;
  late String trip;

  Future<void> openMenu(WidgetTester tester) async {
    h = await ExplorerHarness.create(tester);
    trip = p.join(h.f.paths.landmarks, 'Поход');
    await tester.runAsync(() => Directory(p.join(trip, 'День 1')).create(recursive: true));
    await h.pumpApp(tester);
    await tester.longPress(find.byKey(const Key('folder_row_Поход')));
    await tester.pumpAndSettle();
  }

  testWidgets('long press opens the menu with all 7 items and ОТМЕНА', (tester) async {
    await openMenu(tester);
    expect(find.byKey(const Key('folder_context_menu')), findsOneWidget);
    for (final key in ['open', 'bookmark', 'details', 'copy', 'cut', 'rename', 'delete', 'cancel']) {
      expect(find.byKey(Key('folder_menu_$key')), findsOneWidget, reason: key);
    }
    expect(find.text('БУФЕР ОБМЕНА'), findsOneWidget);
    expect(find.text('ИЗМЕНИТЬ'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Открыть» closes the menu and opens the folder', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder_context_menu')), findsNothing);
    expect(h.f.services.explorerController.state.currentFolder, trip);
    await h.dispose(tester);
  });

  testWidgets('«Закладка» saves the path and says so', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_bookmark')));
    expect(h.f.services.bookmarkController.bookmarks.single.path, trip);
    expect(find.text('Добавлено в закладки'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Детали» opens the details sheet', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder_details_sheet')), findsOneWidget);
    expect(find.text(trip), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Копировать» fills the clipboard; the bar pastes it', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_copy')));
    await tester.pumpAndSettle();
    expect(h.f.services.explorerController.clipboard.entries.single.sourcePath, trip);
    expect(find.text('Скопировано: Поход'), findsWidgets);
    expect(find.byKey(const Key('explorer_clipboard_bar')), findsOneWidget);

    await h.tap(tester, find.byKey(const Key('folder_row_Несортированные метки')));
    await h.tap(tester, find.byKey(const Key('clipboard_paste')));
    expect(await tester.runAsync(() => Directory(p.join(h.f.paths.importDefault, 'Поход')).exists()), isTrue);
    await h.dispose(tester);
  });

  testWidgets('«Вырезать» fills the clipboard as cut', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_cut')));
    expect(h.f.services.explorerController.clipboard.isCut, isTrue);
    expect(find.text('Вырезано: Поход'), findsWidgets);
    await h.dispose(tester);
  });

  testWidgets('«Переименовать» opens the dialog and renames', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_rename')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rename_folder_dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rename_folder_field')), 'Озеро');
    await tester.pump();
    await h.tap(tester, find.byKey(const Key('rename_folder_ok')));
    expect(await tester.runAsync(() => Directory(p.join(h.f.paths.landmarks, 'Озеро')).exists()), isTrue);
    expect(find.byKey(const Key('folder_row_Озеро')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Удалить» asks and deletes', (tester) async {
    await openMenu(tester);
    await h.tap(tester, find.byKey(const Key('folder_menu_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить папку?'), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('confirm_dialog_ok')));
    expect(await tester.runAsync(() => Directory(trip).exists()), isFalse);
    expect(find.text('Папка удалена'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('protected folders answer «Действие недоступно»', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.longPress(find.byKey(const Key('folder_row_Несортированные метки')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('folder_menu_delete')));
    expect(find.text('Действие недоступно'), findsOneWidget);
    expect(await tester.runAsync(() => Directory(h.f.paths.importDefault).exists()), isTrue);
    await h.dispose(tester);
  });

  testWidgets('ОТМЕНА closes without doing anything', (tester) async {
    await openMenu(tester);
    await tester.tap(find.byKey(const Key('folder_menu_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder_context_menu')), findsNothing);
    expect(h.f.services.explorerController.clipboard.isEmpty, isTrue);
    await h.dispose(tester);
  });
}
