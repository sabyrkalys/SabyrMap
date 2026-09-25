import 'package:app/map/info_panel.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  const center = LatLng(47.99580, 37.81465);
  Map<MenuToggle, bool> toggles([Map<MenuToggle, bool> overrides = const {}]) => {
        for (final t in MenuToggle.values) t: t.defaultValue,
        MenuToggle.settingsCenterCoordinates: true,
        MenuToggle.mapsMapScale: true,
        MenuToggle.mapsScaleBar: true,
        ...overrides,
      };

  Future<void> pump(
    WidgetTester tester, {
    Map<MenuToggle, bool>? t,
    LatLng? target,
    bool recording = false,
    double zoom = 6.2,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InfoPanel(center: center, zoom: zoom, target: target, recording: recording, toggles: t ?? toggles()),
          ),
        ),
      ),
    );
  }

  testWidgets('line 1: WGS84 degrees by default, СК-42 X/Y with the toggle', (tester) async {
    await pump(tester);
    expect(find.text('47.99580, 37.81465'), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.settingsSk42Grid: true}));
    expect(find.text('X = 5318741 Y = 7411649'), findsOneWidget);
  });

  testWidgets('line 1 follows «Координаты центра экрана»', (tester) async {
    await pump(tester, t: toggles({MenuToggle.settingsCenterCoordinates: false}));
    expect(find.byKey(const Key('info_line_coordinates')), findsNothing);
  });

  testWidgets('line 2: scale and zoom follow «Масштаб карты», bar follows «Масштабная линейка»', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_scale_text')), findsOneWidget);
    expect(find.text('6/22'), findsOneWidget);
    expect(find.byKey(const Key('info_scale_bar')), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.mapsMapScale: false}));
    expect(find.byKey(const Key('info_scale_text')), findsNothing);
    expect(find.byKey(const Key('info_zoom_text')), findsNothing);
    expect(find.byKey(const Key('info_scale_bar')), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.mapsScaleBar: false}));
    expect(find.byKey(const Key('info_scale_bar')), findsNothing);
  });

  testWidgets('track icon only while recording and «Статус записи трека» is on', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_track_icon')), findsNothing);
    await pump(tester, recording: true);
    expect(find.byKey(const Key('info_track_icon')), findsOneWidget);
    await pump(tester, recording: true, t: toggles({MenuToggle.positioningRecordingStatus: false}));
    expect(find.byKey(const Key('info_track_icon')), findsNothing);
  });

  testWidgets('line 3 only with a target and «Статус цели»', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_line_target')), findsNothing);

    await pump(tester, target: center);
    expect(find.byKey(const Key('info_line_target')), findsOneWidget);
    expect(find.text('→ 0,0 м 0.0°'), findsOneWidget);

    await pump(tester, target: center, t: toggles({MenuToggle.waypointsTargetStatus: false}));
    expect(find.byKey(const Key('info_line_target')), findsNothing);
  });

  testWidgets('everything off hides the whole block', (tester) async {
    await pump(
      tester,
      t: toggles({
        MenuToggle.settingsCenterCoordinates: false,
        MenuToggle.mapsMapScale: false,
        MenuToggle.mapsScaleBar: false,
      }),
    );
    expect(find.byKey(const Key('info_panel')), findsNothing);
  });

  testWidgets('style: semi-transparent light background, rounded, shadow', (tester) async {
    await pump(tester);
    final box = tester.widget<Container>(find.byKey(const Key('info_panel')));
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color!.a, lessThan(1));
    expect(decoration.color!.a, greaterThan(0.5));
    expect(decoration.borderRadius, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });

  test('panel centre ignores a stale live centre once there is no target', () {
    const settled = LatLng(10, 20);
    const stale = LatLng(1, 2);
    expect(infoPanelCenter(target: null, liveCenter: stale, settled: settled), settled);
    expect(infoPanelCenter(target: const LatLng(3, 4), liveCenter: stale, settled: settled), stale);
    expect(infoPanelCenter(target: const LatLng(3, 4), liveCenter: null, settled: settled), settled);
  });

  testWidgets('telemetry wraps instead of overflowing with a large system font on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.topLeft,
                child: InfoPanel(center: center, zoom: 0, recording: true, toggles: toggles()),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('line 3 azimuth runs from the target start to the crosshair', (tester) async {
    // The start is one degree south of the crosshair, so the bearing from
    // it to the crosshair is due north.
    await pump(tester, target: const LatLng(46.99580, 37.81465));
    expect(find.textContaining(' 0.0°'), findsOneWidget);
  });
}
