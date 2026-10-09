import 'dart:convert';
import 'dart:typed_data';

import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:app/landmarks/models/landmark_file.dart';

/// Разбор GeoJSON: FeatureCollection, Feature или голая геометрия.
///
/// - Point / MultiPoint → путевые точки;
/// - LineString → трек из одного сегмента, MultiLineString — по сегменту
///   на линию;
/// - Polygon / MultiPolygon → область (кольца без повтора первой точки);
/// - GeometryCollection делится по геометриям.
///
/// Свойства: name, description (или comment), color (`#RRGGBB`,
/// `#AARRGGBB` или число ARGB).
class GeoJsonParser {
  const GeoJsonParser();

  List<LandmarkObject> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) {
    final Object? json;
    try {
      json = jsonDecode(CharsetDetector.decode(bytes, charset: options.charset));
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic>) throw const FormatException('GeoJSON must be an object');
    final features = switch (json['type']) {
      'FeatureCollection' => (json['features'] as List<dynamic>? ?? const []),
      'Feature' => [json],
      _ => [
        {'type': 'Feature', 'geometry': json, 'properties': const <String, dynamic>{}},
      ],
    };
    final objects = <LandmarkObject>[];
    for (final (i, feature) in features.indexed) {
      try {
        if (feature is! Map<String, dynamic>) throw const FormatException('feature is not an object');
        final properties = feature['properties'] is Map<String, dynamic>
            ? feature['properties'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final geometry = feature['geometry'];
        if (geometry is! Map<String, dynamic>) throw const FormatException('no geometry');
        objects.addAll(_geometry(geometry, _metadata(properties), options, onWarning));
      } on FormatException catch (e) {
        onWarning?.call('Feature $i: ${e.message}, skipped');
      } on TypeError {
        onWarning?.call('Feature $i: malformed coordinates, skipped');
      }
    }
    return objects;
  }

  List<LandmarkObject> _geometry(
    Map<String, dynamic> g,
    LandmarkMetadata metadata,
    ImportOptions options,
    WarningSink? onWarning,
  ) {
    final coords = g['coordinates'];
    LandmarkLocation point(Object? p) {
      final list = p as List<dynamic>;
      if (list.length < 2) throw const FormatException('position needs longitude and latitude');
      return FormatSupport.location(
        (list[1] as num).toDouble(),
        (list[0] as num).toDouble(),
        elevation: list.length > 2 ? (list[2] as num?)?.toDouble() : null,
        options: options,
      );
    }

    List<LandmarkLocation> line(Object? l) => [for (final p in l as List<dynamic>) point(p)];
    AreaPolygon polygon(Object? rings) {
      final list = [for (final r in rings as List<dynamic>) FormatSupport.openRing(line(r))];
      if (list.isEmpty) throw const FormatException('polygon without rings');
      return AreaPolygon(outline: list.first, holes: list.sublist(1));
    }

    return switch (g['type']) {
      'Point' => [WaypointObject(location: point(coords), userMetadata: metadata)],
      'MultiPoint' => [for (final p in coords as List<dynamic>) WaypointObject(location: point(p), userMetadata: metadata)],
      'LineString' => [
        TrackObject(userMetadata: metadata, segments: [TrackSegment(locations: line(coords))]),
      ],
      'MultiLineString' => [
        TrackObject(
          userMetadata: metadata,
          segments: [for (final l in coords as List<dynamic>) TrackSegment(locations: line(l))],
        ),
      ],
      'Polygon' => [
        AreaObject(userMetadata: metadata, polygons: [polygon(coords)]),
      ],
      'MultiPolygon' => [
        AreaObject(userMetadata: metadata, polygons: [for (final p in coords as List<dynamic>) polygon(p)]),
      ],
      'GeometryCollection' => [
        for (final child in g['geometries'] as List<dynamic>? ?? const [])
          ..._geometry(child as Map<String, dynamic>, metadata, options, onWarning),
      ],
      final type => throw FormatException('unsupported geometry "$type"'),
    };
  }

  static LandmarkMetadata _metadata(Map<String, dynamic> p) => FormatSupport.metadata(
    name: p['name']?.toString(),
    description: (p['description'] ?? p['desc'])?.toString(),
    comment: p['comment']?.toString(),
    color: switch (p['color']) {
      final int v when v >= 0 && v <= 0xFFFFFFFF => v,
      final String s => FormatSupport.parseHexColor(s),
      _ => null,
    },
  );
}
