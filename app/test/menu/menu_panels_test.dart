import 'dart:async';

import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/menu/menu_panels.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compass/fakes.dart';
import '../tracks/fake_location_source.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

class _MemoryStore implements MenuTogglesStore {
  Map<String, bool> saved = {};
  @override
  Future<Map<String, bool>> load() async => {...saved};
  @override
  Future<void> save(Map<String, bool> values) async => saved = {...values};
}

class _SlowTracksRepository extends FakeTracksRepository {
  final pending = Completer<Track>();

  @override
  Future<Track> create({
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) =>
      pending.future;
}

void main() {
  Future<ProviderContainer> pumpPanel(
    WidgetTester tester,
    MenuTab tab, {
    FakeLocationSource? locationSource,
    FakeTracksRepository? tracksRepo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
        waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        tracksRepositoryProvider.overrideWithValue(tracksRepo ?? FakeTracksRepository()),
        compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        if (locationSource != null) locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.bottomLeft, child: menuPanelFor(tab, arrowCenterX: 25))),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> expand(WidgetTester tester, String section) async {
    await tester.tap(find.byKey(Key('menu_section_$section')));
    await tester.pumpAndSettle();
  }

  void expectTexts(List<String> texts) {
    for (final text in texts) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  }

  testWidgets('НАСТРОЙКИ content', (tester) async {
    await pumpPanel(tester, MenuTab.settings);
    expectTexts(['НАСТРОЙКИ', 'Скрыть кнопки меню', 'Блокировка экрана', 'Снимок экрана', 'Настройки', 'ОПЦИИ']);
    await expand(tester, 'ОПЦИИ');
    expectTexts(['Координатная сетка СК-42 (Гаусса-Крюгера)', 'Ночной режим', 'Координаты центра экрана']);
  });

  testWidgets('КАРТЫ content', (tester) async {
    await pumpPanel(tester, MenuTab.maps);
    expectTexts(['КАРТЫ', 'Доступные карты', 'Карты на экране', 'Сохранить участок карты', 'Избранные карты', 'ОПЦИИ']);
    await expand(tester, 'ОПЦИИ');
    expectTexts([
      'Использовать только сохранённый кэш карты',
      'Индикаторы загрузки карты',
      'Название карты',
      'Масштаб карты',
      'Масштабная линейка',
    ]);
  });

  testWidgets('МЕТКИ content', (tester) async {
    await pumpPanel(tester, MenuTab.waypoints);
    expectTexts(['МЕТКИ', 'Все метки', 'Метки на экране', 'Новая метка', 'Поиск на карте', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Названия меток', 'Линия до цели', 'Статус цели']);
  });

  testWidgets('ПОЗИЦИОНИРОВАНИЕ content', (tester) async {
    await pumpPanel(tester, MenuTab.positioning);
    expectTexts(['ПОЗИЦИОНИРОВАНИЕ', 'Путевой компьютер', 'Геолокация', 'Запись трека', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Вращать карту по движению', 'Линия расстояния', 'Статус позиционирования', 'Статус записи трека']);
  });

  testWidgets('ОРИЕНТИРОВАНИЕ content', (tester) async {
    await pumpPanel(tester, MenuTab.orientation);
    expectTexts(['ОРИЕНТИРОВАНИЕ', 'Компас', 'ОПЦИИ', 'ИНФОРМЕРЫ']);
    await expand(tester, 'ОПЦИИ');
    await expand(tester, 'ИНФОРМЕРЫ');
    expectTexts(['Вращать карту по компасу', 'Показать компас', 'Статус компаса']);
  });

  testWidgets('checkboxes show the stored value and toggle it', (tester) async {
    final container = await pumpPanel(tester, MenuTab.waypoints);
    await expand(tester, 'ОПЦИИ');

    Checkbox checkboxOf(String label) => tester.widget<Checkbox>(
          find.descendant(of: find.widgetWithText(InkWell, label), matching: find.byType(Checkbox)),
        );
    expect(checkboxOf('Названия меток').value, isTrue);

    await tester.tap(find.text('Названия меток'));
    await tester.pump();
    expect(container.read(menuTogglesProvider)[MenuToggle.waypointsNames], isFalse);
    expect(checkboxOf('Названия меток').value, isFalse);
  });

  testWidgets('«Все метки» opens the waypoints list', (tester) async {
    await pumpPanel(tester, MenuTab.waypoints);
    await tester.tap(find.text('Все метки'));
    await tester.pumpAndSettle();
    expect(find.byType(WaypointsListScreen), findsOneWidget);
  });

  testWidgets('«Компас» switch opens the compass screen and turns off after going back', (tester) async {
    await pumpPanel(tester, MenuTab.orientation);
    Switch compassSwitch() => tester.widget<Switch>(
          find.descendant(of: find.byKey(const Key('compass_switch'), skipOffstage: false), matching: find.byType(Switch, skipOffstage: false)),
        );

    await tester.tap(find.byKey(const Key('compass_switch')));
    await tester.pumpAndSettle();
    expect(find.byType(CompassScreen), findsOneWidget);
    expect(compassSwitch().value, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CompassScreen), findsNothing);
    expect(compassSwitch().value, isFalse);
  });

  testWidgets('«Запись трека» switch mirrors and toggles recording', (tester) async {
    final locationSource = FakeLocationSource();
    final container = await pumpPanel(tester, MenuTab.positioning, locationSource: locationSource);
    Switch recordSwitch() => tester.widget<Switch>(
          find.descendant(of: find.byKey(const Key('track_record_toggle')), matching: find.byType(Switch)),
        );
    expect(recordSwitch().value, isFalse);

    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    expect(container.read(trackRecordingControllerProvider), isA<TrackRecordingActive>());
    expect(recordSwitch().value, isTrue);
  });

  testWidgets('stopping a too-short recording shows a message and does not open the save form', (tester) async {
    final locationSource = FakeLocationSource();
    await pumpPanel(tester, MenuTab.positioning, locationSource: locationSource);

    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Трек слишком короткий, чтобы сохранить'), findsOneWidget);
    expect(find.byKey(const Key('track_name_field')), findsNothing);
  });

  testWidgets('a TrackException on save shows a SnackBar with the error message', (tester) async {
    final locationSource = FakeLocationSource();
    await pumpPanel(
      tester,
      MenuTab.positioning,
      locationSource: locationSource,
      tracksRepo: FakeTracksRepository()..createResult = const TrackException('Could not create track'),
    );

    // Start recording and emit enough points for a valid track.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();
    locationSource.emit(const TrackPoint(lat: 1.1, lng: 2.1));
    await tester.pump();

    // Stop recording -- this opens the save-name sheet.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    // Submit the save form.
    await tester.enterText(find.byKey(const Key('track_name_field')), 'My track');
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Could not create track'), findsOneWidget);
  });

  testWidgets('a track save failure is still reported after the panel closes', (tester) async {
    final locationSource = FakeLocationSource();
    final repo = _SlowTracksRepository();
    final container = ProviderContainer(
      overrides: [
        menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
        tracksRepositoryProvider.overrideWithValue(repo),
        locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);
    var showPanel = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return showPanel
                    ? Align(alignment: Alignment.bottomLeft, child: menuPanelFor(MenuTab.positioning, arrowCenterX: 25))
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();
    locationSource.emit(const TrackPoint(lat: 1.1, lng: 2.1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('track_name_field')), 'My track');
    await tester.tap(find.byKey(const Key('track_save_button')));
    await tester.pumpAndSettle();

    setHostState(() => showPanel = false);
    await tester.pump();
    repo.pending.completeError(const TrackException('Could not create track'));
    await tester.pumpAndSettle();

    expect(find.text('Could not create track'), findsOneWidget);
  });
}
