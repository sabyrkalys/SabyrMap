import 'package:app/landmarks/models/landmark_type.dart';

/// Черновик нового объекта: всё, что UI собрал в диалоге «Новая метка»,
/// до сохранения. В этом спринте сохраняется только [LandmarkType.waypoint].
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
      other.targetFolder == targetFolder;

  @override
  int get hashCode =>
      Object.hash(type, name, comment, description, colorValue, iconId, longitude, latitude, targetFolder);
}
