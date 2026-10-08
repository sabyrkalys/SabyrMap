import 'package:app/map/map_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  testWidgets('zoom buttons: round, shadowed, + above −, each calls back', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapZoomButtons(onZoomIn: () => calls.add('in'), onZoomOut: () => calls.add('out')),
          ),
        ),
      ),
    );

    final zoomIn = find.byKey(const Key('zoom_in_button'));
    final zoomOut = find.byKey(const Key('zoom_out_button'));
    expect(tester.getTopLeft(zoomIn).dy, lessThan(tester.getTopLeft(zoomOut).dy));
    for (final button in [zoomIn, zoomOut]) {
      final material = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
      expect(material.shape, isA<CircleBorder>());
      expect(material.elevation, greaterThan(0));
      expect(material.color, Colors.white);
    }

    await tester.tap(zoomIn);
    await tester.tap(zoomOut);
    expect(calls, ['in', 'out']);
  });

  testWidgets('distance plate: the distance in white on the target colour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: TargetDistanceLabel(from: LatLng(48, 37.8), to: LatLng(48.1, 37.8))),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('11,12 км'));
    expect(text.style!.color, Colors.white);
    final plate = tester.widget<DecoratedBox>(find.ancestor(of: find.byWidget(text), matching: find.byType(DecoratedBox)));
    expect((plate.decoration as BoxDecoration).color, targetColor);
  });

  group('screenOffsetOf', () {
    const center = LatLng(48, 37.8);

    test('the centre itself is at the centre', () {
      expect(screenOffsetOf(center, center: center, zoom: 12, bearing: 0), Offset.zero);
    });

    test('east is right, north is up; one zoom level doubles the distance', () {
      final east = screenOffsetOf(const LatLng(48, 37.81), center: center, zoom: 12, bearing: 0);
      expect(east.dx, greaterThan(0));
      expect(east.dy, closeTo(0, 1e-9));
      // 0.01° of longitude is 512·2^12·0.01/360 px.
      expect(east.dx, closeTo(512 * 4096 * 0.01 / 360, 1e-6));
      expect(screenOffsetOf(const LatLng(48, 37.81), center: center, zoom: 13, bearing: 0).dx, closeTo(east.dx * 2, 1e-6));

      final north = screenOffsetOf(const LatLng(48.01, 37.8), center: center, zoom: 12, bearing: 0);
      expect(north.dx, closeTo(0, 1e-9));
      expect(north.dy, lessThan(0));
    });

    test('a map turned to bearing 90° shows east up', () {
      final east = screenOffsetOf(const LatLng(48, 37.81), center: center, zoom: 12, bearing: 90);
      expect(east.dx, closeTo(0, 1e-6));
      expect(east.dy, lessThan(0));
    });
  });
}
