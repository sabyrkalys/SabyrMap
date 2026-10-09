import 'package:collection/collection.dart';

import 'color_range.dart';

/// Стирание цвета: пиксели, попавшие во все диапазоны, становятся
/// прозрачными.
class EraseColorSettings {
  const EraseColorSettings({this.enabled = false, this.ranges = const [], this.screenCenterHex});

  /// Диапазоны вокруг цвета [argb] по трём каналам.
  factory EraseColorSettings.fromColor(int argb, {int width = ColorRange.defaultWidth, bool enabled = true}) =>
      EraseColorSettings(
        enabled: enabled,
        ranges: [for (var c = 0; c < 3; c++) ColorRange(channel: c, center: (argb >> (16 - 8 * c)) & 0xFF, width: width)],
        screenCenterHex: '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      );

  final bool enabled;

  /// По одному на канал.
  final List<ColorRange> ranges;

  /// Цвет, взятый из-под прицела, `#RRGGBB`.
  final String? screenCenterHex;

  static const Object _keep = Object();

  EraseColorSettings copyWith({bool? enabled, List<ColorRange>? ranges, Object? screenCenterHex = _keep}) =>
      EraseColorSettings(
        enabled: enabled ?? this.enabled,
        ranges: ranges ?? this.ranges,
        screenCenterHex: identical(screenCenterHex, _keep) ? this.screenCenterHex : screenCenterHex as String?,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'ranges': [for (final r in ranges) r.toJson()],
    'screenCenterHex': screenCenterHex,
  };

  factory EraseColorSettings.fromJson(Map<String, dynamic> json) => EraseColorSettings(
    enabled: json['enabled'] as bool? ?? false,
    ranges: [for (final r in json['ranges'] as List<dynamic>? ?? const []) ColorRange.fromJson(r as Map<String, dynamic>)],
    screenCenterHex: json['screenCenterHex'] as String?,
  );

  static const _list = ListEquality<ColorRange>();

  @override
  bool operator ==(Object other) =>
      other is EraseColorSettings &&
      other.enabled == enabled &&
      other.screenCenterHex == screenCenterHex &&
      _list.equals(other.ranges, ranges);

  @override
  int get hashCode => Object.hash(enabled, screenCenterHex, _list.hash(ranges));
}
