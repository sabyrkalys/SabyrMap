import 'dart:math';

import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';

/// Как объект рисуется на карте: точка (значок или кружок), линия,
/// заливка с контуром, подпись.
enum FeatureRole { point, line, fill, label }

/// Метки → GeoJSON для карты. Чистые функции: карта отдаёт результат в
/// источник MapLibre как есть.
///
/// У каждого объекта в `properties`:
/// - `path` — путь метки (у объекта внутри `.ldk` — [LandmarkItem.nestedPath]),
///   по нему нажатие на карте находит метку;
/// - `type` — [LandmarkType.name], `role` — [FeatureRole.name];
/// - `name`, `color` (`#RRGGBB`, если задан), `icon`, `user_icon`, `kind`;
/// - у точки внутри набора, маршрута, трека — `index` (номер точки);
/// - у текста — `text`, `text_size`, `rotation`; у круга — `radius`.
///
/// Decision: координаты в GeoJSON — `[долгота, широта]`; кольца
/// многоугольника замкнуты (первая точка повторена в конце), как требует
/// формат; контур короче трёх точек заливкой не рисуется — только линией.
abstract final class LandmarkFeatures {
  /// Сколько вершин у многоугольника круга.
  static const int circleVertices = 64;

  static const double _earthRadiusMeters = 6371008.8;

  /// Объекты метки [object] с путём [path]; у файла меток — объекты внутри
  /// с путями [LandmarkItem.nestedPath].
  static List<Map<String, dynamic>> of(String path, LandmarkObject object) {
    if (object is LdkFileObject) {
      return [
        for (final (i, child) in object.objects.indexed) ...of(LandmarkItem.nestedPath(path, i), child),
      ];
    }
    final base = _properties(path, object);
    Map<String, dynamic> feature(Map<String, dynamic> geometry, FeatureRole role, [Map<String, dynamic> extra = const {}]) => {
      'type': 'Feature',
      'geometry': geometry,
      'properties': {...base, 'role': role.name, ...extra},
    };
    List<Map<String, dynamic>> points(List<WaypointObject> waypoints) => [
      for (final (i, w) in waypoints.indexed)
        feature(_point(w.location), FeatureRole.point, {
          'index': i,
          if (w.userMetadata.name case final name?) 'name': name,
          if (w.userMetadata.colorValue case final color?) 'color': _hex(color),
        }),
    ];

    return switch (object) {
      WaypointObject(:final location) => [feature(_point(location), FeatureRole.point)],
      SetObject(:final waypoints) => points(waypoints),
      RouteObject(:final waypoints) => [
        if (waypoints.length >= 2) feature(_line([for (final w in waypoints) w.location]), FeatureRole.line),
        ...points(waypoints),
      ],
      TrackObject(:final segments, :final waypoints) => [
        for (final s in segments)
          if (s.locations.length >= 2) feature(_line(s.locations), FeatureRole.line),
        ...points(waypoints),
      ],
      AreaObject(:final polygons) => [
        for (final polygon in polygons)
          if (CompositeCalculator.isClosed(object) && polygon.outline.length >= 3)
            feature(_polygon([polygon.outline, ...polygon.holes]), FeatureRole.fill)
          else if (polygon.outline.length >= 2)
            feature(_line(polygon.outline), FeatureRole.line),
      ],
      CircleObject(:final center, :final radiusMeters) => [
        feature(_polygon([circleOutline(center, radiusMeters)]), FeatureRole.fill, {'radius': radiusMeters}),
      ],
      TextObject(:final location, :final text) => [
        feature(_point(location), FeatureRole.label, {
          'text': text,
          if (object.userMetadata.entries[TextObject.textSizeKey] case final num size) 'text_size': size,
          if (object.userMetadata.entries[TextObject.rotationKey] case final num rotation) 'rotation': rotation,
        }),
      ],
      _ => const [],
    };
  }

  /// `FeatureCollection` из объектов [features].
  static Map<String, dynamic> collection(Iterable<Map<String, dynamic>> features) => {
    'type': 'FeatureCollection',
    'features': features.toList(),
  };

  /// Окружность радиуса [radiusMeters] вокруг [center] на сфере —
  /// [circleVertices] точек по часовой от севера.
  static List<LandmarkLocation> circleOutline(LandmarkLocation center, double radiusMeters) {
    final lat = center.latitude * pi / 180;
    final lon = center.longitude * pi / 180;
    final d = radiusMeters / _earthRadiusMeters;
    return [
      for (var i = 0; i < circleVertices; i++)
        () {
          final bearing = 2 * pi * i / circleVertices;
          final lat2 = asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(bearing));
          final lon2 = lon + atan2(sin(bearing) * sin(d) * cos(lat), cos(d) - sin(lat) * sin(lat2));
          return LandmarkLocation(
            latitude: lat2 * 180 / pi,
            longitude: ((lon2 * 180 / pi) + 540) % 360 - 180,
          );
        }(),
    ];
  }

  static Map<String, dynamic> _properties(String path, LandmarkObject object) {
    final m = object.userMetadata;
    return {
      'path': path,
      'type': object.type.name,
      if (m.name case final name?) 'name': name,
      if (m.colorValue case final color?) 'color': _hex(color),
      if (m.iconId case final icon?) 'icon': icon,
      if (m.userIcon case final icon?) 'user_icon': icon,
      if (m.kind case final kind?) 'kind': kind,
    };
  }

  static List<double> _coord(LandmarkLocation l) => [l.longitude, l.latitude];

  static Map<String, dynamic> _point(LandmarkLocation l) => {'type': 'Point', 'coordinates': _coord(l)};

  static Map<String, dynamic> _line(List<LandmarkLocation> ls) => {
    'type': 'LineString',
    'coordinates': [for (final l in ls) _coord(l)],
  };

  static Map<String, dynamic> _polygon(List<List<LandmarkLocation>> rings) => {
    'type': 'Polygon',
    'coordinates': [
      for (final ring in rings)
        if (ring.isNotEmpty) [for (final l in ring) _coord(l), _coord(ring.first)],
    ],
  };

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
