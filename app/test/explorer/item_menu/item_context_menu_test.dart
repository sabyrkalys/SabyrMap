import 'dart:io';

import 'package:app/explorer/item_menu/item_actions.dart';
import 'package:app/explorer/landmark_item_card.dart';
import 'package:app/explorer/local_landmarks_screen.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/map/map_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_test_harness.dart';
import '../landmark_test_helpers.dart';

void main() {
  late ExplorerHarness h;
  late Map<LandmarkType, String> paths;

  const names = {
    LandmarkType.waypoint: 'Перевал',
    LandmarkType.set: 'Родники',
    LandmarkType.route: 'Маршрут',
    LandmarkType.track: 'Подъём',
    LandmarkType.area: 'Луг',
  };

  Future<void> start(WidgetTester tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async => paths = await createOneOfEach(h.f.services, h.f.paths.landmarks));
    await h.pumpApp(tester);
  }

  Finder rowOf(LandmarkType type) => type == LandmarkType.ldkFile
      ? find.byKey(LandmarkItemCard.keyFor(paths[type]!))
      : find.byKey(Key('item_row_${names[type]}'));

  Future<void> openMenu(WidgetTester tester, LandmarkType type) async {
    final row = rowOf(type);
    await tester.dragUntilVisible(row, find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(row), alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.longPress(row);
    await h.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item_context_menu')), findsOneWidget, reason: type.name);
  }

  /// Нажимает пункт [id]; [until] — чего дождаться после (сообщения).
  Future<void> pick(WidgetTester tester, String id, {Finder? until}) async {
    final item = find.byKey(Key('item_menu_$id'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await h.tap(tester, item);
    // Ждём, пока файл перепишется и список перечитается.
    await pumpUntil(tester, until ?? find.byType(Scaffold));
    // Список и точки на карте перечитываются после сообщения.
    await h.settle(tester);
  }

  Finder inMenu(String text) =>
      find.descendant(of: find.byKey(const Key('item_context_menu')), matching: find.text(text));

  void expectLabels(List<String> labels) {
    for (final label in labels) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
  }

  testWidgets('waypoint: base and edit items', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.waypoint);
    expectLabels([
      'Перевал',
      'Детали',
      'Скрыть',
      'Задать целью',
      'Поделиться',
      'Экспортировать как...',
      'Копировать',
      'Вырезать',
      'Выбрать',
      'Изменить цвет',
      'Изменить свойства',
      'Удалить',
      'ОТМЕНА',
    ]);
    for (final title in ['БУФЕР ОБМЕНА', 'МУЛЬТИВЫБОР', 'ИЗМЕНИТЬ']) {
      expect(inMenu(title), findsOneWidget, reason: title);
    }
    await h.dispose(tester);
  });

  testWidgets('set: auto target and ungroup', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.set);
    expectLabels(['Автомат. цель — ближ. точка', 'Разгруппировать точки', 'Изменить цвет']);
    expect(inMenu('Задать целью'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('route: follow, reverse, convert', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.route);
    expectLabels(['Движение по маршруту', 'Реверс порядка', 'Конвертировать в...']);
    await h.dispose(tester);
  });

  testWidgets('track: follow, dynamic profile, edit profile', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    expectLabels(['Движение по треку', 'Динамический профиль', 'Конвертировать в...', 'Изменить профиль']);
    await h.dispose(tester);
  });

  testWidgets('area: tools; the contour label follows the state', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.area);
    expectLabels(['Инструменты области', 'Разомкнуть контур']);
    await pick(tester, 'closed', until: find.text('Контур разомкнут'));
    expect(find.text('Контур разомкнут'), findsOneWidget);
    await openMenu(tester, LandmarkType.area);
    expectLabels(['Замкнуть контур']);
    await h.dispose(tester);
  });

  testWidgets('landmark file: open and rename', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.ldkFile);
    expectLabels(['Поход', 'Открыть', 'Скрыть', 'Поделиться', 'Экспортировать как...', 'Переименовать', 'Удалить']);
    expect(inMenu('Детали'), findsNothing);
    expect(inMenu('Изменить цвет'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('clipboard: «Копировать» copies, «Вырезать» cuts', (tester) async {
    await start(tester);
    final clipboard = h.f.services.explorerController.clipboard;
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'copy');
    expect(clipboard.entries.single.sourcePath, paths[LandmarkType.track]);
    expect(clipboard.entries.single.type, LandmarkType.track);
    expect(clipboard.isCut, isFalse);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'cut');
    expect(clipboard.isCut, isTrue);
    await h.dispose(tester);
  });

  testWidgets('«Выбрать» activates selection with the item', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.route);
    await pick(tester, 'select');
    final selection = h.f.services.explorerController.selection;
    expect(selection.state.isActive, isTrue);
    expect(selection.snapshot(), {paths[LandmarkType.route]});
    await h.dispose(tester);
  });

  testWidgets('«Задать целью» puts the target on the map', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.waypoint);
    await pick(tester, 'target');
    final container = ProviderScope.containerOf(tester.element(find.byType(LocalLandmarksScreen)));
    final point = container.read(mapTargetProvider).point!;
    expect((point.latitude, point.longitude), (42.87, 74.6));
    expect(find.text('Цель: Перевал'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Изменить цвет» writes the picked colour', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'color');
    expect(find.byKey(const Key('color_picker_sheet')), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('color_ff1565c0')));
    await tester.pumpAndSettle();
    final file = await tester.runAsync(() => h.f.services.repository.load(paths[LandmarkType.track]!));
    expect(file!.content.userMetadata.colorValue, 0xFF1565C0);
    expect(find.text('Цвет изменён'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Реверс порядка» reverses the route', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.route);
    await pick(tester, 'reverse', until: find.text('Порядок точек изменён'));
    final route = await tester.runAsync(() => h.f.services.routeService.load(paths[LandmarkType.route]!));
    expect(route!.waypoints.first.userMetadata.name, 'Финиш');
    await h.dispose(tester);
  });

  testWidgets('a stub says it is not available yet', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.track);
    await pick(tester, 'follow_track');
    expect(find.text(ItemActions.notYet), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Детали» opens the details screen', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.area);
    await pick(tester, 'details');
    await h.settle(tester);
    expect(find.byKey(const Key('landmark_details_screen')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('«Удалить» asks and deletes', (tester) async {
    await start(tester);
    await openMenu(tester, LandmarkType.set);
    await pick(tester, 'delete');
    expect(find.text('Удалить «Родники»?'), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => File(paths[LandmarkType.set]!).exists()), isFalse);
    await h.dispose(tester);
  });
}
