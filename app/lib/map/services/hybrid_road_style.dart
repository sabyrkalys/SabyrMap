import 'dart:convert';

/// Full paint of one line layer of a style. maplibre_gl's setLayerProperties
/// sends every line property, and an unset one falls back to MapLibre's
/// default (black, 1 px, opaque), so nothing here is optional.
class LinePaint {
  const LinePaint({required this.width, required this.color, required this.opacity});

  /// A number or a MapLibre expression.
  final Object width;

  /// A color string or a MapLibre expression.
  final Object color;

  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is LinePaint &&
      jsonEncode(other.width) == jsonEncode(width) &&
      jsonEncode(other.color) == jsonEncode(color) &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(jsonEncode(width), jsonEncode(color), opacity);

  @override
  String toString() => 'LinePaint(width: $width, color: $color, opacity: $opacity)';
}

List<Object> _zoom(num z1, num v1, num z2, num v2) => [
      'interpolate',
      ['linear'],
      ['zoom'],
      z1,
      v1,
      z2,
      v2,
    ];

List<Object> _majorColor(String motorway, String primary) => [
      'match',
      ['get', 'class'],
      ['motorway', 'trunk'],
      motorway,
      primary,
    ];

const _casing = 'rgba(0,0,0,0.35)';

/// Road look over the satellite, adjusted on the phone so it doesn't wait
/// for the server styles to be republished (and their year-long cache).
///
/// Layer ids and the server values are those of the hybrid styles
/// (tools/build/styles/build_styles.py, road_layers with hybrid=true):
/// - major roads (motorway, trunk, primary): 25% narrower, colors 20% darker;
/// - secondary roads (secondary, tertiary, minor, service): as on the
///   server, but opacity 0.55 → 0.45, i.e. 10% more transparent.
///
/// [style] is what the base map was set with: a style URL or style JSON
/// (offline regions). Returns null for anything but our hybrid styles.
Map<String, LinePaint>? hybridRoadPaint(String style) {
  final theme = _hybridTheme(style);
  if (theme == null) return null;
  final night = theme == 'night';
  const major = 0.55;
  const secondary = 0.45;
  return {
    'road-middle-casing': LinePaint(width: _zoom(8, 0.48, 18, 8.8), color: _casing, opacity: secondary),
    // Server: 5, 0.4 → 18, 11.2; × 0.75.
    'road-major-casing': LinePaint(width: _zoom(5, 0.3, 18, 8.4), color: _casing, opacity: major),
    'road-minor': LinePaint(width: _zoom(12, 0.24, 18, 4.4), color: '#ffffff', opacity: secondary),
    'road-middle': LinePaint(
      width: _zoom(8, 0.24, 18, 7.2),
      color: night ? '#5f5a3c' : '#fff0a6',
      opacity: secondary,
    ),
    'road-major': LinePaint(
      // Server: 5, 0.24 → 18, 9.6; × 0.75.
      width: _zoom(5, 0.18, 18, 7.2),
      // Server: day #f2a65a / #ffd57e, night #a8692f / #86743f; each × 0.8.
      color: night ? _majorColor('#865426', '#6b5d32') : _majorColor('#c28548', '#ccaa65'),
      opacity: major,
    ),
  };
}

/// 'day' / 'night' for our hybrid styles, null otherwise.
String? _hybridTheme(String style) {
  final text = style.trimLeft();
  if (text.startsWith('{')) {
    try {
      final metadata = (jsonDecode(text) as Map<String, dynamic>)['metadata'];
      if (metadata is! Map || metadata['sabyrmap:hybrid'] != true) return null;
      return metadata['sabyrmap:theme'] == 'night' ? 'night' : 'day';
    } catch (_) {
      return null;
    }
  }
  final name = Uri.tryParse(text)?.pathSegments.lastOrNull ?? '';
  final match = RegExp(r'^hybrid-(day|night)').firstMatch(name);
  if (match == null || !text.contains('/style/')) return null;
  return match.group(1);
}
