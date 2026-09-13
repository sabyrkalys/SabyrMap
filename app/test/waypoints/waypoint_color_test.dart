import 'package:app/waypoints/waypoint_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colorFromHex parses a 6-digit hex string with full opacity', () {
    final color = colorFromHex('#43A047');

    expect(color.r, closeTo(0x43 / 255, 0.001));
    expect(color.g, closeTo(0xA0 / 255, 0.001));
    expect(color.b, closeTo(0x47 / 255, 0.001));
    expect(color.a, 1.0);
  });

  test('colorToHex formats a Color back to a 6-digit hex string', () {
    const color = Color(0xFF43A047);

    expect(colorToHex(color), '#43A047');
  });

  test('colorFromHex and colorToHex round-trip', () {
    expect(colorToHex(colorFromHex('#1976D2')), '#1976D2');
  });
}
