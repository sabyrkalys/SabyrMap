import 'package:app/app/landmark_services_provider.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/map/drawing/drawing_actions.dart';
import 'package:app/map/drawing/drawing_bar.dart';
import 'package:app/map/drawing/set_panel.dart';
import 'package:app/map/drawing/shape_dialogs.dart';
import 'package:app/waypoints/waypoint_dialog/waypoint_data.dart';
import 'package:app/map/landmark_layer.dart';
import 'package:app/map/map_crosshair.dart';
import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../landmarks/services/fixture.dart';

class _NoopTogglesStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}

LandmarkLocation _loc(double lat, double lon) => LandmarkLocation(latitude: lat, longitude: lon);

void main() {
  group('nextDrawingName', () {
    test('numbers after the highest «Маршрут N» / «Область N»', () {
      expect(nextDrawingName(LandmarkType.route, const []), 'Маршрут 1');
      expect(nextDrawingName(LandmarkType.route, const ['Маршрут 2', 'Маршрут 7', 'Тропа']), 'Маршрут 8');
      expect(nextDrawingName(LandmarkType.area, const ['Маршрут 3']), 'Область 1');
    });
  });

  testWidgets('the bar fits a narrow phone with the app theme (wide buttons there)', (tester) async {
    // NX809J: 1216 px at 3.25 → 374 dp; the theme stretches buttons to the full width.
    tester.view.physicalSize = const Size(1216, 2688);
    tester.view.devicePixelRatio = 3.25;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: DrawingBar(
                type: LandmarkType.area,
                pointCount: 0,
                canUndo: false,
                canRedo: false,
                canFinish: false,
                onAddPoint: () {},
                onUndo: () {},
                onRedo: () {},
                onFinish: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('drawing_bar'))).height, greaterThan(0));
  });

  test('setMetadata keeps what was entered and numbers an unnamed set', () {
    final m = setMetadata(
      const WaypointData(colorValue: 0xFF112233, type: 'danger', comment: ' север ', note: '', website: '', keywords: 'a, b'),
      const ['Набор точек 2'],
    ).entries;
    expect(m[LandmarkMetadata.nameKey], 'Набор точек 3');
    expect(m[LandmarkMetadata.kindKey], 'danger');
    expect(m[LandmarkMetadata.colorKey], 0xFF112233);
    expect(m[LandmarkMetadata.commentKey], 'север');
    expect(m[LandmarkMetadata.keywordsKey], 'a, b');
    expect(m.containsKey(LandmarkMetadata.descriptionKey), isFalse);
    expect(m.containsKey(LandmarkMetadata.websiteKey), isFalse);
  });

  test('parseRadius takes positive metres, with a comma too', () {
    expect(parseRadius('250'), 250);
    expect(parseRadius(' 12,5 '), 12.5);
    expect(parseRadius('0'), isNull);
    expect(parseRadius('-3'), isNull);
    expect(parseRadius('abc'), isNull);
  });

  group('trimTrackEnd', () {
    final line = [_loc(48.5, 37.0), _loc(48.501, 37.0), _loc(48.502, 37.0)];
    final step = Haversine.distance(line[0], line[1]);

    test('cuts into the last stretch: the end moves back along the line', () {
      final cut = trimTrackEnd(line, step / 4);
      expect(cut.keep, 3);
      expect(cut.end!.latitude, closeTo(48.50175, 1e-6));
    });

    test('a cut longer than the last stretch drops it and cuts into the one before', () {
      final cut = trimTrackEnd(line, step * 1.5);
      expect(cut.keep, 2);
      expect(cut.end!.latitude, closeTo(48.5005, 1e-6));
    });

    test('longer than the whole line leaves the first point', () {
      expect(trimTrackEnd(line, step * 5), (keep: 1, end: null));
    });
  });

  test('route length next to the point count', () {
    expect(SetPanel.countLabel(1, 0), '1 точ.');
    expect(SetPanel.countLabel(4, 775.4), '4 точ.   775 м');
    expect(SetPanel.countLabel(3, 2349), '3 точ.   2,35 км');
    expect(SetPanel.countLabel(3), '3 точ.');
  });

  testWidgets('«Управление метками» fits a narrow phone with the app theme', (tester) async {
    tester.view.physicalSize = const Size(1216, 2688);
    tester.view.devicePixelRatio = 3.25;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SetPanel(
              pointCount: 12,
              lengthMeters: 2349,
              onAddPoint: () {},
              onDelete: () {},
              onSearch: () {},
              onFinish: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('12 точ.   2,35 км'), findsOneWidget);
    // Подписи в половинах ряда — одной строкой.
    for (final key in ['set_panel_add', 'set_panel_delete']) {
      final text = find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text));
      expect(tester.getSize(text).height, lessThan(30), reason: key);
    }
    expect(find.text('Путевая точка'), findsOneWidget);
  });

  group('draftFeatures', () {
    List<String> roles(List<Map<String, dynamic>> fs) => [for (final f in fs) (f['properties'] as Map)['role'] as String];

    test('nothing to draw, or a lone point', () {
      expect(LandmarkLayer.draftFeatures(null), isEmpty);
      expect(roles(LandmarkLayer.draftFeatures(RouteObject(waypoints: [WaypointObject(location: _loc(1, 2))]))), [
        'point',
      ]);
    });

    test('a route is a line through its points; only the last point is marked last', () {
      final fs = LandmarkLayer.draftFeatures(
        RouteObject(waypoints: [WaypointObject(location: _loc(1, 2)), WaypointObject(location: _loc(3, 4))]),
      );
      expect(roles(fs), ['line', 'point', 'point']);
      expect((fs[0]['geometry'] as Map)['coordinates'], [
        [2.0, 1.0],
        [4.0, 3.0],
      ]);
      expect([for (final f in fs.skip(1)) (f['properties'] as Map)['last']], [false, true]);
    });

    test('a circle is a closed fill around its centre, with the centre as the only point', () {
      final fs = LandmarkLayer.draftFeatures(CircleObject(center: _loc(48.5, 37), radiusMeters: 500));
      expect(roles(fs), ['fill', 'line', 'point']);
      expect((fs.last['geometry'] as Map)['coordinates'], [37.0, 48.5]);
    });

    test('a set is points only', () {
      final fs = LandmarkLayer.draftFeatures(
        SetObject(waypoints: [WaypointObject(location: _loc(1, 2)), WaypointObject(location: _loc(3, 4))]),
      );
      expect(roles(fs), ['point', 'point']);
    });

    test('an area of two points is an open line; from three it is filled and closed', () {
      AreaObject area(List<LandmarkLocation> outline) => AreaObject(polygons: [AreaPolygon(outline: outline)]);
      expect(roles(LandmarkLayer.draftFeatures(area([_loc(1, 1), _loc(2, 2)]))), ['line', 'point', 'point']);

      final fs = LandmarkLayer.draftFeatures(area([_loc(1, 1), _loc(2, 2), _loc(1, 3)]));
      expect(roles(fs), ['fill', 'line', 'point', 'point', 'point']);
      final line = (fs[1]['geometry'] as Map)['coordinates'] as List;
      expect(line, hasLength(4));
      expect(line.last, line.first);
    });
  });

  group('on the map', () {
    late ServicesFixture f;
    setUp(() async => f = await ServicesFixture.create());
    tearDown(() => f.dispose());

    Future<ProviderContainer> pumpMap(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          menuTogglesStoreProvider.overrideWithValue(_NoopTogglesStore()),
          landmarkServicesProvider.overrideWithValue(f.services),
          onScreenRegistryProvider.overrideWithValue(f.services.onScreen),
          markerGroupFoldersProvider.overrideWithValue(
            MarkerGroupFolders(unsorted: f.paths.importDefault, myMarkers: f.paths.landmarks),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MaterialApp(home: MapScreen())),
      );
      await tester.pump();
      container.read(mapCrosshairProvider.notifier).set(const LatLng(48.5, 37.0));
      return container;
    }

    // Верхняя панель рисования — у области; набор, маршрут и путь рисуются
    // шторкой «Управление метками».
    Future<void> startArea(WidgetTester tester) async {
      f.services.editMode.startNew(LandmarkType.area, folder: f.paths.importDefault);
      await tester.pump();
    }

    String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('drawing_status'))).data!;

    testWidgets('a new area shows the drawing bar; «Точка» adds the point under the crosshair', (tester) async {
      await pumpMap(tester);
      expect(find.byKey(const Key('drawing_bar')), findsNothing);

      await startArea(tester);
      expect(find.text('Новая область'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('drawing_finish'))).onPressed, isNull);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('drawing_add_point')));
        await tester.pump();
      }

      expect(status(tester), 'Точек: 3');
      expect(f.services.editMode.pointCount, 3);
      expect(tester.widget<FilledButton>(find.byKey(const Key('drawing_finish'))).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('drawing_undo')));
      await tester.pump();
      expect(f.services.editMode.pointCount, 2);
    });

    testWidgets('while drawing, a tap on the crosshair adds a point instead of opening the card', (tester) async {
      await pumpMap(tester);
      await startArea(tester);

      await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
      await tester.pump();

      expect(f.services.editMode.pointCount, 1);
      expect(find.byKey(const Key('crosshair_menu_barrier')), findsNothing);
    });

    testWidgets('«Готово» asks for a name and saves the route as a file', (tester) async {
      // Без карты: запись на диск идёт в настоящем времени, а платформенного
      // вида MapLibre под flutter test нет.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('drawing_finish'),
                onPressed: () => finishDrawing(context, f.services),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      f.services.editMode.startNew(LandmarkType.route, folder: f.paths.importDefault);
      await tester.pump();
      f.services.editMode
        ..addPoint(_loc(48.5, 37.0))
        ..addPoint(_loc(48.6, 37.1));
      await tester.pump();

      await tester.tap(find.byKey(const Key('drawing_finish')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('drawing_name_field'))).controller!.text, 'Маршрут 1');
      await tester.enterText(find.byKey(const Key('drawing_name_field')), 'Тропа');
      await tester.tap(find.byKey(const Key('drawing_name_ok')));
      for (var i = 0; i < 100 && f.services.editMode.state.target != null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      for (var i = 0; i < 50 && f.services.index.byType(LandmarkType.route).isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();

      final route = f.services.index.byType(LandmarkType.route).single;
      expect(route.name, 'Тропа');
      expect(route.filePath.startsWith(f.paths.importDefault), isTrue);
      expect(f.services.editMode.state.target, isNull);
      expect(find.text('«Тропа» сохранено'), findsOneWidget);
    });

    Future<ProviderContainer> pumpHost(WidgetTester tester, Future<void> Function(BuildContext, ProviderContainer) action) async {
      final container = ProviderContainer(
        overrides: [
          landmarkServicesProvider.overrideWithValue(f.services),
          markerGroupFoldersProvider.overrideWithValue(
            MarkerGroupFolders(unsorted: f.paths.importDefault, myMarkers: f.paths.landmarks),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(mapCrosshairProvider.notifier).set(const LatLng(48.5, 37.0));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) =>
                    TextButton(onPressed: () => action(context, container), child: const Text('go')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> waitForIndex(WidgetTester tester, LandmarkType type) async {
      for (var i = 0; i < 100 && f.services.index.byType(type).isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('«Круг»: the circle under the crosshair is previewed while the radius is chosen, then saved', (
      tester,
    ) async {
      final container = await pumpHost(tester, createCircleAtCrosshair);
      expect(tester.takeException(), isNull);
      expect((container.read(drawingPreviewProvider) as CircleObject).radiusMeters, 100);
      expect(tester.widget<TextField>(find.byKey(const Key('circle_name_field'))).controller!.text, 'Круг 1');

      await tester.tap(find.byKey(const Key('circle_radius_500')));
      await tester.pump();
      final preview = container.read(drawingPreviewProvider) as CircleObject;
      expect(preview.radiusMeters, 500);
      expect(preview.center.latitude, closeTo(48.5, 1e-9));

      await tester.enterText(find.byKey(const Key('circle_radius_field')), '0');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('circle_ok'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('circle_radius_field')), '750');
      await tester.pump();

      await tester.tap(find.byKey(const Key('circle_ok')));
      await waitForIndex(tester, LandmarkType.circle);

      expect(container.read(drawingPreviewProvider), isNull);
      final item = f.services.index.byType(LandmarkType.circle).single;
      expect(item.name, 'Круг 1');
      final stored = (await tester.runAsync(() => f.services.repository.load(item.path)))!.content as CircleObject;
      expect(stored.radiusMeters, 750);
    });

    testWidgets('«Текст»: the label and its size are saved at the crosshair', (tester) async {
      await pumpHost(tester, createTextAtCrosshair);
      expect(tester.widget<FilledButton>(find.byKey(const Key('text_ok'))).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('text_field')), 'Брод');
      await tester.tap(find.byKey(const Key('text_size_24')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('text_ok')));
      await waitForIndex(tester, LandmarkType.text);

      final item = f.services.index.byType(LandmarkType.text).single;
      expect(item.name, 'Брод');
      final stored = (await tester.runAsync(() => f.services.repository.load(item.path)))!.content as TextObject;
      expect(stored.text, 'Брод');
      expect(stored.userMetadata.entries[TextObject.textSizeKey], 24);
      expect(stored.location.latitude, closeTo(48.5, 1e-6));
    });

    testWidgets('«Готово» saves a set named in its dialog straight away, without asking again', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('drawing_finish'),
                onPressed: () => finishDrawing(context, f.services),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      f.services.editMode
        ..startNew(
          LandmarkType.set,
          folder: f.paths.importDefault,
          metadata: const LandmarkMetadata(entries: {LandmarkMetadata.nameKey: 'Посты'}),
        )
        ..addPoint(_loc(48.5, 37.0));
      await tester.tap(find.byKey(const Key('drawing_finish')));
      await tester.pump();
      expect(find.byKey(const Key('drawing_name_field')), findsNothing);
      for (var i = 0; i < 100 && f.services.index.byType(LandmarkType.set).isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
      expect(f.services.index.byType(LandmarkType.set).single.name, 'Посты');
    });

    testWidgets('the cross closes an empty drawing at once, one with points after a confirmation', (tester) async {
      await pumpMap(tester);
      await startArea(tester);
      await tester.tap(find.byKey(const Key('drawing_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drawing_bar')), findsNothing);

      await startArea(tester);
      f.services.editMode.addPoint(_loc(48.5, 37.0));
      await tester.pump();
      await tester.tap(find.byKey(const Key('drawing_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Закрыть без сохранения?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('drawing_discard')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('drawing_bar')), findsNothing);
      expect(f.services.index.byType(LandmarkType.area), isEmpty);
    });

    Future<void> chooseNewMarker(WidgetTester tester, String title) async {
      await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новая метка...'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(title), 100);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('«Маршрут» opens its dialog, then «Управление метками» with length and «Удалить»', (tester) async {
      await pumpMap(tester);
      await chooseNewMarker(tester, 'Маршрут');
      expect(find.byKey(const Key('set_dialog')), findsOneWidget);
      expect(find.text('Маршрут'), findsWidgets);
      expect(find.byKey(const Key('waypoint_dialog_coords')), findsNothing);
      await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
      await tester.pumpAndSettle();

      final target = f.services.editMode.state.target!;
      expect(target.type, LandmarkType.route);
      expect(target.object.userMetadata.name, 'Маршрут 1');
      expect(find.byKey(const Key('set_panel')), findsOneWidget);
      expect(find.byKey(const Key('set_panel_delete')), findsNothing);

      // Тап по прицелу — обычная карточка, а не точка.
      await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
      await tester.pumpAndSettle();
      expect(f.services.editMode.pointCount, 0);
      expect(find.byKey(const Key('crosshair_menu_barrier')), findsOneWidget);
      await tester.tap(find.byKey(const Key('crosshair_menu_barrier')));
      await tester.pumpAndSettle();

      f.services.editMode
        ..addPoint(_loc(48.5, 37.0))
        ..addPoint(_loc(48.5, 37.01));
      await tester.pump();
      final count = tester.widget<Text>(find.byKey(const Key('set_panel_count'))).data!;
      expect(count, startsWith('2 точ.'));
      expect(count, endsWith(' м'));
      expect(find.byKey(const Key('drawing_leg_label')), findsOneWidget);

      await tester.tap(find.byKey(const Key('set_panel_delete')));
      await tester.pump();
      expect(f.services.editMode.pointCount, 1);
      expect(tester.widget<Text>(find.byKey(const Key('set_panel_count'))).data, '1 точ.');
    });

    testWidgets('«Путь»: dialog without icon, then the panel — «Начертить», «Путевая точка», «Удалить», stats', (
      tester,
    ) async {
      await pumpMap(tester);
      await chooseNewMarker(tester, 'Путь');
      expect(find.byKey(const Key('set_dialog')), findsOneWidget);
      expect(find.byKey(const Key('waypoint_dialog_icon')), findsNothing);
      expect(find.byKey(const Key('waypoint_dialog_coords')), findsNothing);
      await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('more_properties_sheet')), matching: find.text('Иконка')), findsNothing);
      await tester.tap(find.byKey(const Key('more_properties_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
      await tester.pumpAndSettle();

      final target = f.services.editMode.state.target!;
      expect(target.type, LandmarkType.track);
      expect(target.object.userMetadata.name, 'Путь 1');
      expect(find.byKey(const Key('set_panel_draw')), findsOneWidget);
      expect(find.byKey(const Key('drawing_bar')), findsNothing);
      expect(find.text('СТАТИСТИКА'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('set_panel_climb'))).data, 'нет данных о высотах');

      // «Путевая точка» — точка на путь, а не точка линии.
      await tester.tap(find.byKey(const Key('set_panel_add')));
      await tester.pump();
      expect((f.services.editMode.state.target!.object as TrackObject).waypoints, hasLength(1));
      expect(f.services.editMode.pointCount, 0);

      // «Удалить» снимает небольшой отрезок с конца линии, а не весь путь
      // (на масштабе городской карты, 15).
      (tester.state(find.byType(MapScreen)) as dynamic).debugZoom = 15.0;
      for (var i = 0; i < 15; i++) {
        f.services.editMode.addPoint(_loc(48.5 + i * 0.0001, 37.0));
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('set_panel_delete')));
      await tester.pump();
      // 12 dp при масштабе 15 на широте 48.5° — около 19 м (путь ~156 м):
      // путь укоротился ровно на столько, точки не снимались целиком.
      final after = LandmarkLayer.drawnPoints(f.services.editMode.state.target!.object);
      final cut = 14 * 0.0001 * 111195 - Haversine.totalDistance(after);
      expect(cut, closeTo(19, 1));
      expect(after, hasLength(14));
    });

    testWidgets('«Набор точек» opens the waypoint dialog without coordinates, then drawing with what was entered', (
      tester,
    ) async {
      await pumpMap(tester);
      await chooseNewMarker(tester, 'Набор точек');

      expect(find.byKey(const Key('set_dialog')), findsOneWidget);
      expect(find.byKey(const Key('waypoint_dialog_coords')), findsNothing);
      expect(find.byKey(const Key('waypoint_dialog_group')), findsOneWidget);
      expect(f.services.editMode.state.target, isNull);

      await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), 'Посты');
      await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
      await tester.pumpAndSettle();
      // «Ещё...» набора: иконка, цвет, стиль, комментарий, сайт, ключевые слова, описание.
      for (final title in ['Иконка', 'Цвет', 'Стиль', 'Комментарий', 'Сайт', 'Ключевые слова', 'Описание']) {
        expect(find.descendant(of: find.byKey(const Key('more_properties_sheet')), matching: find.text(title)), findsOneWidget);
      }
      expect(find.text('Галерея'), findsNothing);
      await tester.tap(find.text('Сайт'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('waypoint_dialog_website')), 'https://example.org');
      await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ключевые слова'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('waypoint_dialog_keywords')), 'пост, север');
      await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
      await tester.pumpAndSettle();

      final target = f.services.editMode.state.target!;
      expect(target.type, LandmarkType.set);
      expect(target.folder, f.paths.importDefault);
      final m = target.object.userMetadata.entries;
      expect(m[LandmarkMetadata.nameKey], 'Посты');
      expect(m[LandmarkMetadata.websiteKey], 'https://example.org');
      expect(m[LandmarkMetadata.keywordsKey], 'пост, север');
      // Точки набора — панелью «Управление метками», не верхней панелью.
      expect(find.byKey(const Key('set_panel')), findsOneWidget);
      expect(find.byKey(const Key('drawing_bar')), findsNothing);
    });

    Future<void> startSet(WidgetTester tester) async {
      f.services.editMode.startNew(
        LandmarkType.set,
        folder: f.paths.importDefault,
        metadata: const LandmarkMetadata(entries: {LandmarkMetadata.nameKey: 'Посты'}),
      );
      await tester.pump();
    }

    String count(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('set_panel_count'))).data!;

    testWidgets('«Управление метками»: «+ ПУТЕВАЯ ТОЧКА» adds the point under the crosshair; search lists the points', (
      tester,
    ) async {
      await pumpMap(tester);
      await startSet(tester);
      expect(find.text('Управление метками'), findsOneWidget);
      expect(count(tester), '0 точ.');
      expect(tester.widget<IconButton>(find.byKey(const Key('set_panel_search'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('set_panel_add')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('set_panel_add')));
      await tester.pump();
      expect(count(tester), '2 точ.');

      await tester.tap(find.byKey(const Key('set_panel_search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('set_point_1')), findsOneWidget);
      expect(find.text('Точка 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('set_point_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('set_points_sheet')), findsNothing);
    });

    testWidgets('the tick with no points just closes; system back closes an empty drawing too', (tester) async {
      await pumpMap(tester);
      await startSet(tester);
      await tester.tap(find.byKey(const Key('set_panel_done')));
      await tester.pump();
      expect(f.services.editMode.state.target, isNull);
      expect(find.byKey(const Key('set_panel')), findsNothing);

      await startSet(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(f.services.editMode.state.target, isNull);
    });

    testWidgets('«Новая метка» → «Область» starts drawing an area', (tester) async {
      await pumpMap(tester);
      await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новая метка...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Область'));
      await tester.pumpAndSettle();

      expect(f.services.editMode.state.target?.type, LandmarkType.area);
      expect(find.text('Новая область'), findsOneWidget);
    });
  });
}
