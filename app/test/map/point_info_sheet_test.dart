import 'package:app/map/point_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('formatAngleEw', () {
    expect(formatAngleEw(8.14), '8.1° В');
    expect(formatAngleEw(-0.62), '0.6° З');
    expect(formatAngleEw(0.02), '0.0°');
    expect(formatAngleEw(-0.04), '0.0°');
  });

  test('formatUtcOffset', () {
    expect(formatUtcOffset(const Duration(hours: 3)), 'UTC+3');
    expect(formatUtcOffset(const Duration(hours: 5, minutes: 30)), 'UTC+5:30');
    expect(formatUtcOffset(const Duration(hours: -3, minutes: -30)), 'UTC−3:30');
    expect(formatUtcOffset(Duration.zero), 'UTC+0');
  });

  test('formatClock', () {
    expect(formatClock(DateTime(2026, 9, 25, 5, 3)), '05:03');
    expect(formatClock(null), '—');
  });

  Future<void> pump(WidgetTester tester, {required bool sk42}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PointInfoSheet(point: const LatLng(47.9958, 37.81465), sk42: sk42, now: DateTime(2026, 9, 25, 12)),
        ),
      ),
    );
  }

  testWidgets('title and the five rows in order', (tester) async {
    await pump(tester, sk42: false);
    expect(find.text('ИНФОРМАЦИЯ'), findsOneWidget);
    const labels = [
      'Координаты',
      'Склонение (магнитное)',
      'Конвергенция меридианов',
      'Время восхода и заката',
      'Часовой пояс',
    ];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getTopLeft(find.text(labels[i])).dy,
        greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        reason: labels[i],
      );
    }
    expect(find.text('47.99580, 37.81465'), findsOneWidget);
    expect(find.text('0.9° З'), findsOneWidget); // convergence −0.88°
    expect(find.byKey(const Key('point_info_sunrise_icon')), findsOneWidget);
    expect(find.byKey(const Key('point_info_sunset_icon')), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
  });

  testWidgets('coordinates follow the СК-42 setting', (tester) async {
    await pump(tester, sk42: true);
    expect(find.text('X = 5318741 Y = 7411649'), findsOneWidget);
  });

  testWidgets('declination row shows a value with a side letter', (tester) async {
    await pump(tester, sk42: false);
    final value = tester.widget<Text>(find.byKey(const Key('point_info_declination'))).data!;
    expect(value, matches(RegExp(r'^\d+\.\d° [ВЗ]$|^0\.0°$')));
  });

  testWidgets('long СК-42 coordinates fit a narrow phone with a large font', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PointInfoSheet(point: const LatLng(47.9958, 37.81465), sk42: true, now: DateTime(2026, 9, 25, 12)),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('СК-42 coordinates stay on one line on a 411 dp phone at the default font', (tester) async {
    // flutter test renders with a 1-em-per-glyph test font unless a real
    // font is loaded; widths only mean something with the app's Roboto.
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
    await roboto.load();
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, sk42: true);
    final coordinates = tester.getSize(find.byKey(const Key('point_info_coordinates'))).height;
    final declination = tester.getSize(find.byKey(const Key('point_info_declination'))).height;
    expect(coordinates, declination, reason: 'coordinates must not wrap onto a second line');
  });
}

