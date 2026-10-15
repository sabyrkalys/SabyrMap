import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/explorer/details/landmark_details_screen.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/map/map_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../landmarks/services/fixture.dart';
import '../landmark_test_helpers.dart';

void main() {
  late ServicesFixture f;
  late Map<LandmarkType, String> paths;
  late ProviderContainer container;

  Future<void> pumpDetails(WidgetTester tester, LandmarkType type) async {
    await tester.runAsync(() async {
      f = await ServicesFixture.create();
      paths = await createOneOfEach(f.services, f.paths.landmarks);
    });
    container = ProviderContainer(overrides: [landmarkServicesProvider.overrideWithValue(f.services)]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: LandmarkDetailsScreen(path: paths[type]!)),
      ),
    );
    await pumpUntil(tester, find.byKey(const Key('details_body')));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.runAsync(() async => f.root.deleteSync(recursive: true));
  }

  String value(WidgetTester tester, String label) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(Key('details_field_$label')), matching: find.byType(Text)))
      .last
      .data!;

  Finder section(String title) => find.byKey(Key('details_section_$title'));

  testWidgets('track: ФАЙЛ, СТАТИСТИКА, СЕГМЕНТЫ, СОБЫТИЯ and the profile', (tester) async {
    await pumpDetails(tester, LandmarkType.track);
    for (final title in ['ФАЙЛ', 'СТАТИСТИКА', 'СЕГМЕНТЫ', 'СОБЫТИЯ']) {
      expect(section(title), findsOneWidget, reason: title);
    }
    expect(find.byKey(const Key('details_profile_preview')), findsOneWidget);
    expect(value(tester, 'Имя'), 'Подъём');
    expect(value(tester, 'Подъём'), '200 м');
    expect(value(tester, 'Спуск'), '50 м');
    expect(value(tester, 'Мин/Макс высота'), '1500 м / 1700 м');
    expect(value(tester, 'Калории'), startsWith('≈ '));
    expect(find.text('Сегмент 1'), findsOneWidget);
    expect(find.text('Сегмент 2'), findsOneWidget);
    expect(find.text('Привал'), findsOneWidget);
    expect(find.text('Наибольшая высота'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('waypoint: ФАЙЛ, КООРДИНАТЫ, АВТОР И ВРЕМЯ', (tester) async {
    await pumpDetails(tester, LandmarkType.waypoint);
    for (final title in ['ФАЙЛ', 'КООРДИНАТЫ', 'АВТОР И ВРЕМЯ']) {
      expect(section(title), findsOneWidget, reason: title);
    }
    expect(value(tester, 'Широта'), '42.870000°N');
    expect(value(tester, 'Долгота'), '74.600000°E');
    expect(value(tester, 'X'), matches(RegExp(r'^\d+$')));
    expect(value(tester, 'Y'), matches(RegExp(r'^\d+$')));
    expect(value(tester, 'Высота'), '—');
    expect(value(tester, 'Дата создания'), matches(RegExp(r'^\d\d\.\d\d\.\d{4} \d\d:\d\d:\d\d$')));
    final size = await tester.runAsync(() => File(paths[LandmarkType.waypoint]!).length());
    expect(value(tester, 'Размер'), '$size Б');
    expect(value(tester, 'Папка'), f.paths.landmarks);
    await dispose(tester);
  });

  testWidgets('area: ФАЙЛ, СТАТИСТИКА with area and perimeter', (tester) async {
    await pumpDetails(tester, LandmarkType.area);
    expect(section('ФАЙЛ'), findsOneWidget);
    expect(section('СТАТИСТИКА'), findsOneWidget);
    expect(value(tester, 'Площадь'), isNot('—'));
    expect(value(tester, 'Периметр'), isNot('—'));
    expect(find.byKey(const Key('details_geometry_preview')), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('route legs and set points are listed', (tester) async {
    await pumpDetails(tester, LandmarkType.route);
    expect(section('ПЛЕЧИ'), findsOneWidget);
    expect(find.text('Старт → Финиш'), findsOneWidget);
    expect(value(tester, 'Количество точек'), '2');
    await dispose(tester);

    await pumpDetails(tester, LandmarkType.set);
    expect(section('ТОЧКИ'), findsOneWidget);
    expect(find.text('Родник 1'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('landmark file: no ЦЕНТРИРОВАТЬ, a СОДЕРЖИМОЕ section', (tester) async {
    await pumpDetails(tester, LandmarkType.ldkFile);
    expect(find.byKey(const Key('details_center')), findsNothing);
    expect(section('СОДЕРЖИМОЕ'), findsOneWidget);
    expect(find.text('В файле нет объектов'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a section collapses and expands', (tester) async {
    await pumpDetails(tester, LandmarkType.track);
    expect(find.byKey(const Key('details_field_Длина')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('details_toggle_СТАТИСТИКА')));
    await tester.tap(find.byKey(const Key('details_toggle_СТАТИСТИКА')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('details_field_Длина')), findsNothing);
    await tester.tap(find.byKey(const Key('details_toggle_СТАТИСТИКА')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('details_field_Длина')), findsOneWidget);
    await dispose(tester);
  });

  for (final key in ['maps_more_button', 'details_more', 'details_more_ФАЙЛ']) {
    testWidgets('⋮ ($key) opens the compact item menu', (tester) async {
      await pumpDetails(tester, LandmarkType.track);
      await tester.tap(find.byKey(Key(key)));
      await pumpUntil(tester, find.byKey(const Key('item_context_menu_compact')));
      final menu = find.byKey(const Key('item_context_menu_compact'));
      expect(menu, findsOneWidget);
      for (final label in ['Поделиться', 'Экспортировать как...', 'Изменить цвет', 'Удалить']) {
        expect(find.descendant(of: menu, matching: find.text(label)), findsOneWidget, reason: label);
      }
      for (final label in ['Детали', 'Копировать', 'Вырезать', 'Выбрать', 'БУФЕР ОБМЕНА', 'МУЛЬТИВЫБОР']) {
        expect(find.descendant(of: menu, matching: find.text(label)), findsNothing, reason: label);
      }
      await dispose(tester);
    });
  }

  testWidgets('the eye toggles the map display', (tester) async {
    await pumpDetails(tester, LandmarkType.track);
    final path = paths[LandmarkType.track]!;
    await tester.tap(find.byKey(const Key('details_visibility')));
    await tester.pump();
    expect(f.services.displayRegistry.isDisplayed(path), isTrue);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byKey(const Key('details_visibility')));
    await tester.pump();
    expect(f.services.displayRegistry.isDisplayed(path), isFalse);
    await dispose(tester);
  });

  testWidgets('ЦЕНТРИРОВАТЬ asks the map to move to the object', (tester) async {
    await pumpDetails(tester, LandmarkType.route);
    expect(container.read(mapFocusProvider), isNull);
    await tester.tap(find.byKey(const Key('details_center')));
    await tester.pump();
    final focus = container.read(mapFocusProvider)!;
    expect(focus.point.latitude, closeTo(42.81, 1e-9));
    expect(focus.point.longitude, closeTo(74.515, 1e-9));
    await dispose(tester);
  });

  testWidgets('renaming a landmark file from the compact menu updates the screen', (tester) async {
    await pumpDetails(tester, LandmarkType.ldkFile);
    await tester.tap(find.byKey(const Key('details_more')));
    await pumpUntil(tester, find.byKey(const Key('item_context_menu_compact')));
    await tester.tap(find.byKey(const Key('item_menu_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ldk_rename_field')), 'Сборы');
    await tester.runAsync(() => tester.tap(find.byKey(const Key('ldk_rename_ok'))));
    await pumpUntil(tester, find.text('Файл переименован'));
    await pumpUntil(tester, find.descendant(of: find.byKey(const Key('details_field_Имя')), matching: find.text('Сборы')));
    expect(value(tester, 'Имя'), 'Сборы');
    expect(find.text('Поход'), findsNothing);
    await dispose(tester);
  });

  testWidgets('deleting from the compact menu closes the details', (tester) async {
    await tester.runAsync(() async {
      f = await ServicesFixture.create();
      paths = await createOneOfEach(f.services, f.paths.landmarks);
    });
    container = ProviderContainer(overrides: [landmarkServicesProvider.overrideWithValue(f.services)]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('host_button'),
                onPressed: () => LandmarkDetailsScreen.open(context, paths[LandmarkType.area]!),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await pumpUntil(tester, find.byKey(const Key('details_body')));
    await tester.tap(find.byKey(const Key('details_more')));
    await pumpUntil(tester, find.byKey(const Key('item_context_menu_compact')));
    await tester.ensureVisible(find.byKey(const Key('item_menu_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item_menu_delete')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.byKey(const Key('confirm_dialog_ok'))));
    await pumpUntil(tester, find.byKey(const Key('host_button')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.byKey(const Key('landmark_details_screen')), findsNothing);
    expect(await tester.runAsync(() => File(paths[LandmarkType.area]!).exists()), isFalse);
    await dispose(tester);
  });
}
