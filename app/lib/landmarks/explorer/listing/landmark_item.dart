import 'package:app/landmarks/models/landmark_type.dart';

/// Файл метки в списке проводника: заголовок и пользовательские
/// метаданные, без содержимого (точек, сегментов).
class LandmarkItem {
  const LandmarkItem({
    required this.path,
    required this.name,
    required this.type,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    required this.fileSizeBytes,
    required this.fileModifiedAt,
    this.iconId,
    this.latitude,
    this.longitude,
    this.lengthMeters,
    this.durationMs,
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.areaSquareMeters,
    this.activity,
    this.year,
  });

  /// Цвет, если в метаданных его нет.
  static const int defaultColor = 0xFFEE1111;

  final String path;
  final String name;
  final LandmarkType type;

  /// Цвет ARGB.
  final int colorValue;
  final String? iconId;

  /// Время создания и правки, Unix ms.
  final int createdAt;
  final int updatedAt;

  final int fileSizeBytes;
  final DateTime fileModifiedAt;

  /// Координата путевой точки; у остальных типов — null.
  final double? latitude;
  final double? longitude;

  final double? lengthMeters;
  final int? durationMs;
  final double? elevationGainMeters;
  final double? elevationLossMeters;
  final double? areaSquareMeters;
  final String? activity;
  final int? year;

  /// Год для группировки: [year] или год создания (местное время).
  int get effectiveYear => year ?? DateTime.fromMillisecondsSinceEpoch(createdAt).year;

  static const Object _keep = Object();

  /// Копия с заменёнными полями. Для полей, которые могут быть null,
  /// явный null очищает значение; пропуск — сохраняет.
  LandmarkItem copyWith({
    String? path,
    String? name,
    LandmarkType? type,
    int? colorValue,
    Object? iconId = _keep,
    int? createdAt,
    int? updatedAt,
    int? fileSizeBytes,
    DateTime? fileModifiedAt,
    Object? latitude = _keep,
    Object? longitude = _keep,
    Object? lengthMeters = _keep,
    Object? durationMs = _keep,
    Object? elevationGainMeters = _keep,
    Object? elevationLossMeters = _keep,
    Object? areaSquareMeters = _keep,
    Object? activity = _keep,
    Object? year = _keep,
  }) => LandmarkItem(
    path: path ?? this.path,
    name: name ?? this.name,
    type: type ?? this.type,
    colorValue: colorValue ?? this.colorValue,
    iconId: identical(iconId, _keep) ? this.iconId : iconId as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    fileModifiedAt: fileModifiedAt ?? this.fileModifiedAt,
    latitude: identical(latitude, _keep) ? this.latitude : latitude as double?,
    longitude: identical(longitude, _keep) ? this.longitude : longitude as double?,
    lengthMeters: identical(lengthMeters, _keep) ? this.lengthMeters : lengthMeters as double?,
    durationMs: identical(durationMs, _keep) ? this.durationMs : durationMs as int?,
    elevationGainMeters: identical(elevationGainMeters, _keep) ? this.elevationGainMeters : elevationGainMeters as double?,
    elevationLossMeters: identical(elevationLossMeters, _keep) ? this.elevationLossMeters : elevationLossMeters as double?,
    areaSquareMeters: identical(areaSquareMeters, _keep) ? this.areaSquareMeters : areaSquareMeters as double?,
    activity: identical(activity, _keep) ? this.activity : activity as String?,
    year: identical(year, _keep) ? this.year : year as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is LandmarkItem &&
      other.path == path &&
      other.name == name &&
      other.type == type &&
      other.colorValue == colorValue &&
      other.iconId == iconId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.fileSizeBytes == fileSizeBytes &&
      other.fileModifiedAt == fileModifiedAt &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.lengthMeters == lengthMeters &&
      other.durationMs == durationMs &&
      other.elevationGainMeters == elevationGainMeters &&
      other.elevationLossMeters == elevationLossMeters &&
      other.areaSquareMeters == areaSquareMeters &&
      other.activity == activity &&
      other.year == year;

  @override
  int get hashCode => Object.hashAll([
    path,
    name,
    type,
    colorValue,
    iconId,
    createdAt,
    updatedAt,
    fileSizeBytes,
    fileModifiedAt,
    latitude,
    longitude,
    lengthMeters,
    durationMs,
    elevationGainMeters,
    elevationLossMeters,
    areaSquareMeters,
    activity,
    year,
  ]);

  @override
  String toString() => 'LandmarkItem(${type.extension}, $name, $path)';
}
