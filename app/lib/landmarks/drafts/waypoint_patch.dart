/// Частичная правка путевой точки. null — поле не меняется; пустая строка
/// у текстовых полей и `iconId` — значение удаляется.
class WaypointPatch {
  const WaypointPatch({
    this.name,
    this.comment,
    this.description,
    this.colorValue,
    this.iconId,
    this.longitude,
    this.latitude,
    this.extra = const {},
  });

  /// Прочие ключи метаданных: значение ставится, null — ключ удаляется.
  final Map<String, Object?> extra;

  final String? name;
  final String? comment;
  final String? description;

  /// Цвет ARGB.
  final int? colorValue;
  final String? iconId;

  /// Новая долгота; меняется только вместе с [latitude] или отдельно.
  final double? longitude;
  final double? latitude;

  /// Правка ничего не меняет.
  bool get isEmpty =>
      name == null &&
      comment == null &&
      description == null &&
      colorValue == null &&
      iconId == null &&
      longitude == null &&
      latitude == null &&
      extra.isEmpty;

  /// В правке есть координата.
  bool get hasLocation => longitude != null || latitude != null;
}
