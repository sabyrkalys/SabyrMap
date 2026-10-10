import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/composite/statistics/energy_estimate.dart';

import 'landmark_item.dart';
import 'sort_direction.dart';

export 'sort_direction.dart';

/// По чему сортируется список.
enum SortField {
  name,
  date,
  distanceFromScreenCenter,
  length,
  duration,
  elevationGain,
  area,

  /// Наибольшая высота.
  maxElevation,

  /// Средний уклон: (подъём + спуск) / длина.
  slope,

  /// Средняя скорость: длина / время.
  speed,

  /// Оценка калорий по длине и подъёму ([EnergyEstimate]).
  calories,
}

/// Сортировка списка проводника.
///
/// Decision:
/// - `date` — время создания;
/// - элементы без значения поля (нет координаты, длины...) всегда в конце,
///   в любом направлении;
/// - равные элементы упорядочены по имени, затем по пути — порядок
///   устойчив и не зависит от исходного.
class SortOptions {
  const SortOptions({this.field = SortField.name, this.direction = SortDirection.ascending});

  final SortField field;
  final SortDirection direction;

  SortOptions copyWith({SortField? field, SortDirection? direction}) =>
      SortOptions(field: field ?? this.field, direction: direction ?? this.direction);

  /// Нужна ли для этой сортировки точка центра экрана.
  bool get needsScreenCenter => field == SortField.distanceFromScreenCenter;

  /// Отсортированная копия [items]. Сортировка по расстоянию без [center]
  /// возвращает список в исходном порядке.
  List<LandmarkItem> apply(List<LandmarkItem> items, {({double latitude, double longitude})? center}) {
    if (needsScreenCenter && center == null) return List.of(items);
    final keyed = [for (final item in items) (item, _key(item, center))];
    keyed.sort((a, b) {
      final (ia, ka) = a;
      final (ib, kb) = b;
      if (ka == null || kb == null) {
        if (ka != null) return -1;
        if (kb != null) return 1;
      } else {
        final byKey = Comparable.compare(ka, kb);
        if (byKey != 0) return direction == SortDirection.ascending ? byKey : -byKey;
      }
      return _tieBreak(ia, ib);
    });
    return [for (final (item, _) in keyed) item];
  }

  /// Строка формата `field:direction` для настроек.
  String encode() => '${field.name}:${direction.name}';

  /// Обратно из [encode]; неизвестная строка — null.
  static SortOptions? decode(String? text) {
    final parts = text?.split(':');
    if (parts == null || parts.length != 2) return null;
    final field = SortField.values.where((f) => f.name == parts[0]).firstOrNull;
    final direction = SortDirection.values.where((d) => d.name == parts[1]).firstOrNull;
    if (field == null || direction == null) return null;
    return SortOptions(field: field, direction: direction);
  }

  Comparable<Object>? _key(LandmarkItem item, ({double latitude, double longitude})? center) => switch (field) {
    SortField.name => item.name.toLowerCase(),
    SortField.date => item.createdAt,
    SortField.distanceFromScreenCenter =>
      item.latitude == null || item.longitude == null
          ? null
          : distanceMeters(center!.latitude, center.longitude, item.latitude!, item.longitude!),
    SortField.length => item.lengthMeters,
    SortField.duration => item.durationMs,
    SortField.elevationGain => item.elevationGainMeters,
    SortField.area => item.areaSquareMeters,
    SortField.maxElevation => item.maxElevationMeters,
    SortField.slope => _slope(item),
    SortField.speed => _speed(item),
    SortField.calories => item.lengthMeters == null
        ? null
        : EnergyEstimate.kcal(item.lengthMeters!, gainMeters: item.elevationGainMeters ?? 0),
  };

  static double? _slope(LandmarkItem item) {
    final length = item.lengthMeters;
    final gain = item.elevationGainMeters;
    if (length == null || length <= 0 || gain == null) return null;
    return (gain + (item.elevationLossMeters ?? 0)) / length;
  }

  static double? _speed(LandmarkItem item) {
    final length = item.lengthMeters;
    final duration = item.durationMs;
    if (length == null || duration == null || duration <= 0) return null;
    return length / (duration / 1000);
  }

  static int _tieBreak(LandmarkItem a, LandmarkItem b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.path.compareTo(b.path);
  }

  /// Расстояние по большому кругу (гаверсинус), метры.
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) =>
      Haversine.distanceDegrees(lat1, lon1, lat2, lon2);

  @override
  bool operator ==(Object other) => other is SortOptions && other.field == field && other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);

  @override
  String toString() => 'SortOptions(${encode()})';
}
