import 'dart:io';

import 'package:app/explorer/ldk/ldk_item_card.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_test_harness.dart';
import 'ldk_test_helpers.dart';

void main() {
  late ExplorerHarness h;
  late String path;

  Future<void> openMenu(WidgetTester tester, {bool create = true}) async {
    if (create) {
      h = await ExplorerHarness.create(tester);
      await tester.runAsync(() async => path = await createLdk(h.f.services, 'Поход'));
      await h.pumpApp(tester);
    }
    await tester.longPress(find.byKey(LdkItemCard.keyFor(path)));
    await h.settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key('ldk_menu_$key')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(Key('ldk_menu_$key')));
    await tester.pumpAndSettle();
  }

  testWidgets('the full menu has every item and ОТМЕНА', (tester) async {
    await openMenu(tester);
    for (final label in [
      'Открыть',
      'Показать',
      'Поделиться',
      'Экспортировать как...',
      'Копировать',
      'Вырезать',
      'Выбрать',
      'Переименовать',
      'Изменить свойства',
      'Удалить',
      'ОТМЕНА',
    ]) {
      expect(find.descendant(of: find.byKey(const Key('ldk_context_menu')), matching: find.text(label)), findsOneWidget,
          reason: label);
    }
    for (final section in ['БУФЕР ОБМЕНА', 'МУЛЬТИВЫБОР', 'ИЗМЕНИТЬ']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    await h.dispose(tester);
  });

  testWidgets('ОТМЕНА closes the menu without doing anything', (tester) async {
    await openMenu(tester);
    await pick(tester, 'cancel');
    expect(find.byKey(const Key('ldk_context_menu')), findsNothing);
    expect(await tester.runAsync(() => File(path).exists()), isTrue);
    await h.dispose(tester);
  });

  testWidgets('«Открыть» opens the details screen', (tester) async {
    await openMenu(tester);
    await pick(tester, 'open');
    await h.settle(tester);
    expect(find.byKey(const Key('ldk_details_screen')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Показать» toggles the map display and the label becomes «Скрыть»', (tester) async {
    await openMenu(tester);
    await pick(tester, 'display');
    expect(h.f.services.displayRegistry.isDisplayed(path), isTrue);
    await openMenu(tester, create: false);
    expect(find.text('Скрыть'), findsOneWidget);
    await pick(tester, 'display');
    expect(h.f.services.displayRegistry.isDisplayed(path), isFalse);
    await h.dispose(tester);
  });

  testWidgets('«Поделиться» without a platform layer explains itself', (tester) async {
    await openMenu(tester);
    await pick(tester, 'share');
    expect(find.text('Отправка файлов на этом устройстве недоступна'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Копировать» and «Вырезать» fill the clipboard', (tester) async {
    await openMenu(tester);
    await pick(tester, 'copy');
    final clipboard = h.f.services.explorerController.clipboard;
    expect(clipboard.entries.single.sourcePath, path);
    expect(clipboard.entries.single.type, LandmarkType.ldkFile);
    expect(clipboard.isCut, isFalse);
    expect(find.byKey(const Key('explorer_clipboard_bar')), findsOneWidget);
    await openMenu(tester, create: false);
    await pick(tester, 'cut');
    expect(clipboard.isCut, isTrue);
    await h.dispose(tester);
  });

  testWidgets('«Выбрать» activates selection with the file', (tester) async {
    await openMenu(tester);
    await pick(tester, 'select');
    final selection = h.f.services.explorerController.selection;
    expect(selection.state.isActive, isTrue);
    expect(selection.contains(path), isTrue);
    expect(find.byKey(const Key('explorer_selection_bar')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Экспортировать как...» starts the export flow', (tester) async {
    await openMenu(tester);
    await pick(tester, 'export');
    await h.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_export_formats')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Переименовать» opens the dialog and renames', (tester) async {
    await openMenu(tester);
    await pick(tester, 'rename');
    expect(find.byKey(const Key('ldk_rename_dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ldk_rename_field')), 'Сборы');
    await h.tap(tester, find.byKey(const Key('ldk_rename_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Файл переименован'), findsOneWidget);
    expect(find.text('Сборы'), findsOneWidget);
    expect(await tester.runAsync(() => File(path).exists()), isFalse);
    await h.dispose(tester);
  });

  testWidgets('«Изменить свойства» opens the properties dialog and saves', (tester) async {
    await openMenu(tester);
    await pick(tester, 'properties');
    expect(find.byKey(const Key('ldk_properties_dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ldk_props_comment')), 'Весна');
    await h.tap(tester, find.byKey(const Key('ldk_props_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Свойства обновлены'), findsOneWidget);
    final file = await tester.runAsync(() => h.f.services.repository.load(path));
    expect(file!.content.userMetadata.entries['comment'], 'Весна');
    await h.dispose(tester);
  });

  testWidgets('«Удалить» asks and deletes on confirmation', (tester) async {
    await openMenu(tester);
    await pick(tester, 'delete');
    expect(find.text('Удалить файл?'), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => File(path).exists()), isFalse);
    expect(find.byKey(const Key('ldk_section')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('«Удалить» → «Отмена» keeps the file', (tester) async {
    await openMenu(tester);
    await pick(tester, 'delete');
    await h.tap(tester, find.byKey(const Key('confirm_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => File(path).exists()), isTrue);
    await h.dispose(tester);
  });
}
