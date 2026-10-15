import 'dart:math';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';

/// По чему сортируются «Метки на экране».
enum OnScreenSortField { type, name, date, distance, altitude, icon }

/// Сортировка «Меток на экране». Decision: как в [SortOptions] — без
/// значения поля (нет координаты, высоты, иконки) всегда в конце, равные —
/// по имени, затем по пути.
class OnScreenSort {
  const OnScreenSort({this.field = OnScreenSortField.name, this.ascending = true});

  final OnScreenSortField field;
  final bool ascending;

  /// Строка для настроек: `field:asc|desc`.
  String encode() => '${field.name}:${ascending ? 'asc' : 'desc'}';

  /// Обратно из [encode]; неизвестная строка — null.
  static OnScreenSort? decode(String? text) {
    final parts = text?.split(':');
    if (parts == null || parts.length != 2 || !const {'asc', 'desc'}.contains(parts[1])) return null;
    final field = OnScreenSortField.values.where((f) => f.name == parts[0]).firstOrNull;
    return field == null ? null : OnScreenSort(field: field, ascending: parts[1] == 'asc');
  }

  /// Отсортированная копия [items]; [center] — центр экрана (без него
  /// сортировка по расстоянию оставляет порядок по имени).
  List<LandmarkItem> apply(List<LandmarkItem> items, {({double latitude, double longitude})? center}) {
    final keyed = [for (final item in items) (item, _key(item, center))];
    keyed.sort((a, b) {
      final (ia, ka) = a;
      final (ib, kb) = b;
      if (ka == null || kb == null) {
        if (ka != null) return -1;
        if (kb != null) return 1;
      } else {
        final byKey = Comparable.compare(ka, kb);
        if (byKey != 0) return ascending ? byKey : -byKey;
      }
      final byName = ia.name.toLowerCase().compareTo(ib.name.toLowerCase());
      return byName != 0 ? byName : ia.path.compareTo(ib.path);
    });
    return [for (final (item, _) in keyed) item];
  }

  Comparable<Object>? _key(LandmarkItem item, ({double latitude, double longitude})? center) => switch (field) {
    OnScreenSortField.type => item.type.index,
    OnScreenSortField.name => item.name.toLowerCase(),
    OnScreenSortField.date => item.createdAt,
    OnScreenSortField.distance => distanceFrom(center, item),
    OnScreenSortField.altitude => item.maxElevationMeters,
    OnScreenSortField.icon => item.iconId,
  };

  /// Расстояние от [center] до точки [item], м; null — у метки нет точки
  /// или центр неизвестен.
  static double? distanceFrom(({double latitude, double longitude})? center, LandmarkItem item) {
    if (center == null || item.latitude == null || item.longitude == null) return null;
    return SortOptions.distanceMeters(center.latitude, center.longitude, item.latitude!, item.longitude!);
  }

  /// Направление от [center] на точку [item], градусы от севера по часовой.
  static double? bearingFrom(({double latitude, double longitude})? center, LandmarkItem item) {
    if (center == null || item.latitude == null || item.longitude == null) return null;
    double rad(double d) => d * pi / 180;
    final lat1 = rad(center.latitude);
    final lat2 = rad(item.latitude!);
    final dLon = rad(item.longitude! - center.longitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  @override
  bool operator ==(Object other) => other is OnScreenSort && other.field == field && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}
