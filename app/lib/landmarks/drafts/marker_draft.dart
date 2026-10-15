import 'package:app/landmarks/models/landmark_type.dart';

/// Черновик нового объекта: всё, что UI собрал в диалоге «Новая метка»,
/// до сохранения: путевая точка, круг ([radiusMeters]), текст ([text]) или
/// файл меток. Составные объекты — свои черновики (SetDraft...).
class MarkerDraft {
  const MarkerDraft({
    required this.type,
    required this.longitude,
    required this.latitude,
    this.name,
    this.comment,
    this.description,
    this.colorValue,
    this.iconId,
    this.targetFolder,
    this.extraMetadata = const {},
    this.radiusMeters,
    this.text,
  });

  final LandmarkType type;
  final String? name;
  final String? comment;
  final String? description;

  /// Цвет ARGB.
  final int? colorValue;

  /// ID иконки из [IconRegistry].
  final String? iconId;

  /// Долгота, градусы WGS84.
  final double longitude;

  /// Широта, градусы WGS84.
  final double latitude;

  /// Папка сохранения; null — папка по умолчанию.
  final String? targetFolder;

  /// Прочие ключи пользовательских метаданных (например, тип метки
  /// приложения); значения — допустимые типы [LandmarkMetadata].
  final Map<String, Object> extraMetadata;

  /// Радиус круга, м ([LandmarkType.circle]); центр — [latitude]/[longitude].
  final double? radiusMeters;

  /// Надпись ([LandmarkType.text]) в точке [latitude]/[longitude].
  final String? text;

  MarkerDraft copyWith({
    LandmarkType? type,
    String? name,
    String? comment,
    String? description,
    int? colorValue,
    String? iconId,
    double? longitude,
    double? latitude,
    String? targetFolder,
    Map<String, Object>? extraMetadata,
    double? radiusMeters,
    String? text,
  }) => MarkerDraft(
    type: type ?? this.type,
    name: name ?? this.name,
    comment: comment ?? this.comment,
    description: description ?? this.description,
    colorValue: colorValue ?? this.colorValue,
    iconId: iconId ?? this.iconId,
    longitude: longitude ?? this.longitude,
    latitude: latitude ?? this.latitude,
    targetFolder: targetFolder ?? this.targetFolder,
    extraMetadata: extraMetadata ?? this.extraMetadata,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    text: text ?? this.text,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkerDraft &&
      other.type == type &&
      other.name == name &&
      other.comment == comment &&
      other.description == description &&
      other.colorValue == colorValue &&
      other.iconId == iconId &&
      other.longitude == longitude &&
      other.latitude == latitude &&
      other.targetFolder == targetFolder &&
      other.radiusMeters == radiusMeters &&
      other.text == text;

  @override
  int get hashCode =>
      Object.hash(type, name, comment, description, colorValue, iconId, longitude, latitude, targetFolder, radiusMeters, text);
}
