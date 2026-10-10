import 'dart:io';

import 'package:app/explorer/landmark_item_card.dart';
import 'package:app/explorer/section_menu/section_actions.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_test_harness.dart';
import '../landmark_test_helpers.dart';

void main() {
  late ExplorerHarness h;
  late Map<LandmarkType, String> paths;

  Future<void> start(WidgetTester tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async => paths = await createOneOfEach(h.f.services, h.f.paths.landmarks));
    await h.pumpApp(tester);
  }

  /// Прокручивает список к [finder] и ставит его ближе к середине — не
  /// под кнопку «+».
  Future<void> reveal(WidgetTester tester, Finder finder, Finder scrollable) async {
    await tester.dragUntilVisible(finder, scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, LandmarkType type) async {
    await reveal(tester, find.byKey(Key('section_menu_${type.extension}')), find.byType(ListView).first);
    await tester.tap(find.byKey(Key('section_menu_${type.extension}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('section_context_menu')), findsOneWidget);
  }

  /// Пункт шторки: прокрутить к нему и нажать.
  Future<void> pick(WidgetTester tester, String id) async {
    final item = find.byKey(Key('section_menu_$id'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await h.tap(tester, item);
    await tester.pumpAndSettle();
  }

  Finder inSheet(String text) =>
      find.descendant(of: find.byKey(const Key('section_context_menu')), matching: find.text(text));

  testWidgets('tracks: title «Треки», every section, «Сгруппировать все» and statistics sorts', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    expect(inSheet('Треки'), findsOneWidget);
    for (final label in [
      'Показать все',
      'Убрать все',
      'Экспортировать как...',
      'Копировать все',
      'Вырезать все',
      'Сгруппировать все',
      'Изменить свойства',
      'Удалить все',
      'Список',
      'Предварительный просмотр',
      'Выбрать все',
      'Отменить все',
      'Имя (a-z)',
      'Дата (9-1)',
      'Расстояние от центра экрана (1-9)',
      'Длина (1-9)',
      'Калории (9-1)',
    ]) {
      expect(inSheet(label), findsOneWidget, reason: label);
    }
    for (final title in [
      'БУФЕР ОБМЕНА',
      'ИЗМЕНИТЬ',
      'РЕЖИМ ОТОБРАЖЕНИЯ',
      'МУЛЬТИВЫБОР',
      'СОРТИРОВАТЬ ПО',
      'СОРТИРОВАТЬ ПО (СТАТИСТИКА)',
    ]) {
      expect(inSheet(title), findsOneWidget, reason: title);
    }
    await h.dispose(tester);
  });

  testWidgets('sets: «Наборы точек» without grouping and statistics', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.set);
    expect(inSheet('Наборы точек'), findsOneWidget);
    expect(inSheet('Сгруппировать все'), findsNothing);
    expect(inSheet('СОРТИРОВАТЬ ПО (СТАТИСТИКА)'), findsNothing);
    expect(inSheet('Расстояние от центра экрана (1-9)'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('areas: «Области» with sort by area; landmark files: «Файлы меток»', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.area);
    expect(inSheet('Области'), findsOneWidget);
    expect(inSheet('Площадь (1-9)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('section_menu_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('section_menu_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('section_context_menu')), findsNothing);
    await openMenu(tester, LandmarkType.ldkFile);
    expect(inSheet('Файлы меток'), findsOneWidget);
    expect(inSheet('Сгруппировать все'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('«Выбрать все» selects the section; «Отменить все» clears it', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'select_all');
    final selection = h.f.services.explorerController.selection;
    expect(selection.state.isActive, isTrue);
    expect(selection.snapshot(), {paths[LandmarkType.track]});
    expect(find.text('Выбрано: 1'), findsOneWidget);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'clear_selection');
    expect(selection.snapshot(), isEmpty);
    await h.dispose(tester);
  });

  testWidgets('view mode is saved and switches rows to cards', (tester) async {
    await start(tester);
    final track = paths[LandmarkType.track]!;
    expect(find.byKey(LandmarkItemCard.keyFor(track)), findsNothing);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'view_preview');
    expect(find.byKey(const Key('section_context_menu')), findsNothing);
    expect(h.f.services.settings.getString(SectionActions.viewModeKey(LandmarkType.track)), 'preview');
    await reveal(tester, find.byKey(LandmarkItemCard.keyFor(track)), find.byType(ListView).first);
    expect(find.byKey(LandmarkItemCard.keyFor(track)), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('sorting is saved and keeps the sheet open', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'sort_length_desc');
    expect(find.byKey(const Key('section_context_menu')), findsOneWidget);
    expect(h.f.services.settings.getString(SectionActions.sortKey(LandmarkType.track)), 'length:descending');
    final selected = tester.widget<Icon>(
      find.descendant(of: find.byKey(const Key('section_menu_sort_length_desc')), matching: find.byType(Icon)),
    );
    expect(selected.icon, Icons.radio_button_checked);
    await h.dispose(tester);
  });

  testWidgets('«Показать все» / «Убрать все» toggle the whole section on the map', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'show_all');
    expect(h.f.services.displayRegistry.isDisplayed(paths[LandmarkType.track]!), isTrue);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'hide_all');
    expect(h.f.services.displayRegistry.isDisplayed(paths[LandmarkType.track]!), isFalse);
    await h.dispose(tester);
  });

  testWidgets('«Удалить все» asks and deletes the section files', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.area);
    await pick(tester, 'delete_all');
    expect(find.text('Удалить все (1)?'), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => File(paths[LandmarkType.area]!).exists()), isFalse);
    expect(await tester.runAsync(() => File(paths[LandmarkType.track]!).exists()), isTrue);
    expect(find.byKey(const Key('section_are')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('track section subtitle sums length and gain', (tester) async {
    await start(tester);
    await reveal(tester, find.byKey(const Key('section_subtitle_trk')), find.byType(ListView).first);
    final text = tester.widget<Text>(find.byKey(const Key('section_subtitle_trk'))).data!;
    expect(text, matches(RegExp(r'^1 элем\. \d+,\d км \+200 м$')));
    await h.dispose(tester);
  });
}
