import 'dart:convert';

import 'package:app/map/services/hybrid_road_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'https://192.168.1.120/tiles/style';

  test('day hybrid styles: major roads narrower and darker, ordinary roads more transparent', () {
    for (final name in ['hybrid-day', 'hybrid-day-nobuildings']) {
      final paint = hybridRoadPaint('$base/$name')!;
      expect(paint['road-major']!.width, ['interpolate', ['linear'], ['zoom'], 5, 0.18, 18, 7.2]);
      expect(paint['road-major-casing']!.width, ['interpolate', ['linear'], ['zoom'], 5, 0.3, 18, 8.4]);
      expect(paint['road-major']!.color, ['match', ['get', 'class'], ['motorway', 'trunk'], '#c28548', '#ccaa65']);
      expect(paint['road-major']!.opacity, 0.55);
      // Secondary roads keep the server look, only 10% more transparent.
      expect(
        paint['road-minor'],
        const LinePaint(width: ['interpolate', ['linear'], ['zoom'], 12, 0.24, 18, 4.4], color: '#ffffff', opacity: 0.45),
      );
      expect(
        paint['road-middle'],
        const LinePaint(width: ['interpolate', ['linear'], ['zoom'], 8, 0.24, 18, 7.2], color: '#fff0a6', opacity: 0.45),
      );
      expect(paint['road-middle-casing']!.color, 'rgba(0,0,0,0.35)');
      expect(paint['road-major-casing']!.color, 'rgba(0,0,0,0.35)');
    }
  });

  test('night hybrid darkens its own night colors', () {
    final paint = hybridRoadPaint('$base/hybrid-night')!;
    expect(paint['road-major']!.color, ['match', ['get', 'class'], ['motorway', 'trunk'], '#865426', '#6b5d32']);
    expect(paint['road-middle']!.color, '#5f5a3c');
  });

  test('an offline region is recognised by the style metadata', () {
    String style(Map<String, Object> metadata) => jsonEncode({'version': 8, 'metadata': metadata, 'layers': []});
    expect(hybridRoadPaint(style({'sabyrmap:hybrid': true, 'sabyrmap:theme': 'day'})), isNotNull);
    expect(hybridRoadPaint(style({'sabyrmap:hybrid': true, 'sabyrmap:theme': 'night'}))!['road-major']!.color,
        contains('#865426'));
    expect(hybridRoadPaint(style({'sabyrmap:hybrid': false, 'sabyrmap:theme': 'day'})), isNull);
  });

  test('vector-only and foreign styles are left alone', () {
    expect(hybridRoadPaint('$base/vector-day'), isNull);
    expect(hybridRoadPaint('https://tiles.openfreemap.org/styles/liberty'), isNull);
    expect(hybridRoadPaint('{not json'), isNull);
  });
}
