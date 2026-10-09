import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';

/// Общее для адаптеров форматов: точки с высотой и временем, метаданные.
abstract final class FormatSupport {
  /// Точка с необязательными высотой (метры) и временем (Unix ms) с учётом
  /// опций импорта.
  static LandmarkLocation location(
    double lat,
    double lon, {
    double? elevation,
    int? timeMs,
    double? accuracyMeters,
    ImportOptions options = const ImportOptions(),
  }) {
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw FormatException('Coordinates out of range: $lat, $lon');
    }
    return LandmarkLocation(
      latitude: lat,
      longitude: lon,
      values: [
        if (accuracyMeters != null)
          LocationValue(type: LocationValueType.accuracy, value: (accuracyMeters * 100).round()),
        if (elevation != null && options.elevation.readsElevation)
          LocationValue(type: LocationValueType.elevation, value: (elevation * 1000).round()),
        if (timeMs != null) LocationValue(type: LocationValueType.utcTime, value: options.fixTime(timeMs)),
      ],
    );
  }

  /// Высота точки, метры.
  static double? elevationOf(LandmarkLocation l) => switch (l.valueOf(LocationValueType.elevation)?.value) {
    final int raw => raw / 1000,
    _ => null,
  };

  /// Время точки, Unix ms.
  static int? timeOf(LandmarkLocation l) => switch (l.valueOf(LocationValueType.utcTime)?.value) {
    final int t => t,
    _ => null,
  };

  /// Точность точки, метры.
  static double? accuracyOf(LandmarkLocation l) => switch (l.valueOf(LocationValueType.accuracy)?.value) {
    final int raw => raw / 100,
    _ => null,
  };

  /// Время ISO 8601 → Unix ms; не время — null.
  static int? parseIsoTime(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return DateTime.tryParse(text.trim())?.toUtc().millisecondsSinceEpoch;
  }

  /// Unix ms → ISO 8601 UTC (`2026-10-09T12:00:00Z`, мс — если не ноль).
  static String isoTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final s = t.toIso8601String();
    return t.millisecond == 0 && t.microsecond == 0 ? '${s.substring(0, 19)}Z' : s;
  }

  /// Пользовательские метаданные из текстовых полей файла (пустые — без ключа).
  static LandmarkMetadata metadata({String? name, String? comment, String? description, int? color, String? icon}) =>
      LandmarkMetadata(
        entries: {
          if (name?.trim().isNotEmpty ?? false) LandmarkMetadata.nameKey: name!.trim(),
          if (comment?.trim().isNotEmpty ?? false) LandmarkMetadata.commentKey: comment!.trim(),
          if (description?.trim().isNotEmpty ?? false) LandmarkMetadata.descriptionKey: description!.trim(),
          LandmarkMetadata.colorKey: ?color,
          if (icon?.trim().isNotEmpty ?? false) LandmarkMetadata.iconKey: icon!.trim(),
        },
      );

  /// `#RRGGBB` / `#AARRGGBB` / `RRGGBB` → ARGB; иначе null.
  static int? parseHexColor(String? text) {
    final hex = text?.trim().replaceFirst('#', '');
    if (hex == null || !RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) return null;
    final value = int.parse(hex, radix: 16);
    return hex.length == 6 ? 0xFF000000 | value : value;
  }

  /// ARGB → `AARRGGBB` (заглавные).
  static String hexColor(int argb) => (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();

  /// Убирает повтор первой точки в конце замкнутого кольца.
  static List<LandmarkLocation> openRing(List<LandmarkLocation> ring) =>
      ring.length > 1 && ring.first.latitude == ring.last.latitude && ring.first.longitude == ring.last.longitude
      ? ring.sublist(0, ring.length - 1)
      : ring;
}
