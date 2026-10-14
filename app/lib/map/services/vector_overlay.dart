/// A vector map laid over the map as a layer: the drawable layers of its
/// style (lines, labels, areas, and raster imagery such as the satellite of
/// a hybrid) without its background, with source and layer ids prefixed so
/// they live next to the map's own.
class VectorOverlay {
  const VectorOverlay({required this.sources, required this.layers});

  /// Vector layer types; the chosen map scales their opacity too.
  static const Set<String> drawableTypes = {'line', 'symbol', 'fill', 'circle', 'fill-extrusion'};

  /// Layer types taken into an overlay; the background stays behind.
  static const Set<String> overlayTypes = {...drawableTypes, 'raster'};

  /// Source types an overlay draws from.
  static const Set<String> sourceTypes = {'vector', 'raster'};

  /// Opacity paint properties of each layer type.
  static const Map<String, List<String>> opacityProperties = {
    'line': ['line-opacity'],
    'fill': ['fill-opacity'],
    'fill-extrusion': ['fill-extrusion-opacity'],
    'symbol': ['text-opacity', 'icon-opacity'],
    'circle': ['circle-opacity', 'circle-stroke-opacity'],
    'raster': ['raster-opacity'],
  };

  /// Prefixed source id → its style JSON (vector and raster sources).
  final Map<String, Map<String, dynamic>> sources;

  /// Prefixed layers, bottom → top, with their own opacity.
  final List<Map<String, dynamic>> layers;

  static String prefixed(String overlayId, String id) => '$overlayId~$id';

  /// The overlay [overlayId] made of [style] (a MapLibre style JSON).
  factory VectorOverlay.fromStyle(String overlayId, Map<String, dynamic> style) {
    final styleSources = (style['sources'] as Map<String, dynamic>? ?? const {});
    final vectorSources = {
      for (final e in styleSources.entries)
        if (sourceTypes.contains((e.value as Map<String, dynamic>)['type'])) e.key: e.value as Map<String, dynamic>,
    };
    final layers = <Map<String, dynamic>>[
      for (final raw in (style['layers'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic> &&
            overlayTypes.contains(raw['type']) &&
            vectorSources.containsKey(raw['source']))
          {
            ...raw,
            'id': prefixed(overlayId, raw['id'] as String),
            'source': prefixed(overlayId, raw['source'] as String),
          },
    ];
    final used = {for (final l in layers) l['source'] as String};
    return VectorOverlay(
      sources: {
        for (final e in vectorSources.entries)
          if (used.contains(prefixed(overlayId, e.key))) prefixed(overlayId, e.key): e.value,
      },
      layers: layers,
    );
  }

  String get bottomLayerId => layers.first['id'] as String;

  /// [layer] with each opacity scaled by [factor] (0..1): a number is
  /// multiplied; a zoom curve keeps its stops and scales their values.
  static Map<String, dynamic> withOpacity(Map<String, dynamic> layer, double factor) {
    final paint = Map<String, dynamic>.of(layer['paint'] as Map<String, dynamic>? ?? const {});
    for (final property in opacityProperties[layer['type']] ?? const <String>[]) {
      paint[property] = scaleOpacity(paint[property], factor);
    }
    return {...layer, 'paint': paint};
  }

  static Object scaleOpacity(Object? value, double factor) {
    if (value == null) return factor;
    if (value is num) return value * factor;
    if (value is List && value.isNotEmpty) {
      final op = value.first;
      // ["interpolate", type, ["zoom"], z1, v1, z2, v2...]
      if (op == 'interpolate' && value.length > 3) {
        return [
          ...value.take(3),
          for (var i = 3; i < value.length; i++) (i - 3).isOdd ? scaleOpacity(value[i], factor) : value[i],
        ];
      }
      // ["step", ["zoom"], v0, z1, v1...]
      if (op == 'step' && value.length > 2) {
        return [
          ...value.take(2),
          for (var i = 2; i < value.length; i++) (i - 2).isEven ? scaleOpacity(value[i], factor) : value[i],
        ];
      }
      return ['*', value, factor];
    }
    return factor;
  }
}
