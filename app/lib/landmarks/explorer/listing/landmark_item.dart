import 'package:app/landmarks/models/landmark_type.dart';

/// Файл метки в списке проводника: заголовок и пользовательские
/// метаданные, без содержимого (точек, сегментов).
class LandmarkItem {
  const LandmarkItem({
    required this.path,
    required this.name,
    required this.type,
    this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    required this.fileSizeBytes,
    required this.fileModifiedAt,
    this.iconId,
    this.userIcon,
    this.kind,
    this.description,
    this.latitude,
    this.longitude,
    this.lengthMeters,
    this.durationMs,
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.maxElevationMeters,
    this.areaSquareMeters,
    this.activity,
    this.year,
  });

  /// Цвет, если в метаданных его нет.
  static const int defaultColor = 0xFFEE1111;

  /// Путь объекта внутри файла меток: `<путь .ldk>#ldk:<номер>`.
  static const String _nestedMark = '#ldk:';

  static String nestedPath(String ldkPath, int index) => '$ldkPath$_nestedMark$index';

  /// Файл, в котором лежит объект [path]: у вложенного в `.ldk` — сам
  /// `.ldk`, у остальных — [path].
  static String fileOf(String path) {
    final at = path.lastIndexOf(_nestedMark);
    return at == -1 ? path : path.substring(0, at);
  }

  /// Объект внутри файла меток (только для показа: правится файл целиком).
  bool get isNested => path.contains(_nestedMark);

  /// Файл, в котором лежит объект ([fileOf]).
  String get filePath => fileOf(path);

  final String path;
  final String name;
  final LandmarkType type;

  /// Свой цвет ARGB; null — не задан (у точки — цвет её вида).
  final int? colorValue;

  /// Цвет для показа в списках: свой или [defaultColor].
  int get displayColor => colorValue ?? defaultColor;
  final String? iconId;

  /// Файл значка из библиотеки ([LandmarkMetadata.userIcon]).
  final String? userIcon;

  /// Вид метки в приложении ([LandmarkMetadata.kind]).
  final String? kind;
  final String? description;

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

  /// Наибольшая высота, м.
  final double? maxElevationMeters;
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
    Object? colorValue = _keep,
    Object? iconId = _keep,
    Object? userIcon = _keep,
    Object? kind = _keep,
    Object? description = _keep,
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
    Object? maxElevationMeters = _keep,
    Object? areaSquareMeters = _keep,
    Object? activity = _keep,
    Object? year = _keep,
  }) => LandmarkItem(
    path: path ?? this.path,
    name: name ?? this.name,
    type: type ?? this.type,
    colorValue: identical(colorValue, _keep) ? this.colorValue : colorValue as int?,
    iconId: identical(iconId, _keep) ? this.iconId : iconId as String?,
    userIcon: identical(userIcon, _keep) ? this.userIcon : userIcon as String?,
    kind: identical(kind, _keep) ? this.kind : kind as String?,
    description: identical(description, _keep) ? this.description : description as String?,
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
    maxElevationMeters: identical(maxElevationMeters, _keep) ? this.maxElevationMeters : maxElevationMeters as double?,
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
      other.userIcon == userIcon &&
      other.kind == kind &&
      other.description == description &&
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
      other.maxElevationMeters == maxElevationMeters &&
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
    userIcon,
    kind,
    description,
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
    maxElevationMeters,
    areaSquareMeters,
    activity,
    year,
  ]);

  @override
  String toString() => 'LandmarkItem(${type.extension}, $name, $path)';
}
