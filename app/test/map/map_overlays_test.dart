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

  testWidgets('distance label shows the formatted distance in orange', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: TargetDistanceLabel(from: LatLng(48, 37.8), to: LatLng(48, 37.8))),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('0.0 м'));
    expect(text.style!.color, targetColor);
  });
}
