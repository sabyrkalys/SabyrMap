import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Набор именованных значений, привязанный к объекту метки.
///
/// Словарь ключей sabyrmap:
///
/// | Ключ          | Тип    | Значение                                   |
/// |---------------|--------|--------------------------------------------|
/// | `name`        | String | Имя объекта                                |
/// | `comment`     | String | Комментарий                                |
/// | `description` | String | Описание                                   |
/// | `color`       | int    | Цвет ARGB                                  |
/// | `icon`        | String | ID иконки                                  |
/// | `style`       | String | JSON-строка со стилем (сериализованный Map)|
/// | `created_at`  | int    | Время создания, Unix ms                    |
/// | `updated_at`  | int    | Время последней правки, Unix ms            |
/// | `length_m`    | double | Длина трека/маршрута, метры                |
/// | `duration_ms` | int    | Длительность трека, мс                     |
/// | `elevation_gain_m` | double | Набор высоты, метры                   |
/// | `elevation_loss_m` | double | Сброс высоты, метры                   |
/// | `area_m2`     | double | Площадь области, м²                        |
/// | `activity`    | String | Вид активности (пешком, авто...)           |
/// | `year`        | int    | Год, к которому относится объект           |
/// | `closed`      | bool   | Замкнут ли контур области (нет — true)     |
///
/// Допустимые типы значений: [bool], [int] (64 бита), [double], [String],
/// [Uint8List] (сырые байты). Любой другой тип — [SerializationException]
/// при записи. Незнакомые ключи сохраняются как есть.
class LandmarkMetadata {
  const LandmarkMetadata({this.entries = const {}, this.version = 0});

  static const String nameKey = 'name';
  static const String commentKey = 'comment';
  static const String descriptionKey = 'description';
  static const String colorKey = 'color';
  static const String iconKey = 'icon';

  /// Файл значка из библиотеки пользователя (папка icons); [iconKey] —
  /// значок из каталога. Могут быть оба.
  static const String userIconKey = 'user_icon';

  /// Вид метки в приложении (тип путевой точки: «Пост», «Опасность»...).
  static const String kindKey = 'type';
  static const String styleKey = 'style';
  static const String createdAtKey = 'created_at';
  static const String updatedAtKey = 'updated_at';
  static const String lengthKey = 'length_m';
  static const String durationKey = 'duration_ms';
  static const String elevationGainKey = 'elevation_gain_m';
  static const String elevationLossKey = 'elevation_loss_m';
  static const String maxElevationKey = 'max_elevation_m';
  static const String areaKey = 'area_m2';
  static const String activityKey = 'activity';
  static const String yearKey = 'year';
  static const String closedKey = 'closed';

  /// Записи метаданных; порядок ключей сохраняется при записи.
  final Map<String, dynamic> entries;

  /// Версия набора метаданных; растёт на 1 при каждой правке файла.
  final int version;

  LandmarkMetadata copyWith({Map<String, dynamic>? entries, int? version}) =>
      LandmarkMetadata(entries: entries ?? this.entries, version: version ?? this.version);

  /// Копия с добавленными (или заменёнными) записями.
  LandmarkMetadata withEntries(Map<String, dynamic> updates) =>
      copyWith(entries: {...entries, ...updates});

  bool get isEmpty => entries.isEmpty && version == 0;

  String? get name => _typed<String>(nameKey);
  String? get comment => _typed<String>(commentKey);
  String? get description => _typed<String>(descriptionKey);
  int? get colorValue => _typed<int>(colorKey);
  String? get iconId => _typed<String>(iconKey);
  String? get userIcon => _typed<String>(userIconKey);
  String? get kind => _typed<String>(kindKey);
  int? get createdAtMs => _typed<int>(createdAtKey);
  int? get updatedAtMs => _typed<int>(updatedAtKey);

  /// Стиль, разобранный из JSON-строки под ключом `style`.
  ///
  /// Decision: в файле стиль хранится строкой (тип Map формат не умеет),
  /// поэтому геттер разбирает JSON; если строка не JSON-объект — null.
  Map<String, dynamic>? get style {
    final raw = _typed<String>(styleKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Упаковывает стиль в JSON-строку для записи под ключом `style`.
  static String encodeStyle(Map<String, dynamic> style) => jsonEncode(style);

  T? _typed<T>(String key) {
    final v = entries[key];
    return v is T ? v : null;
  }

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is LandmarkMetadata && other.version == version && _equality.equals(other.entries, entries);

  @override
  int get hashCode => Object.hash(version, _equality.hash(entries));

  @override
  String toString() => 'LandmarkMetadata(v$version, $entries)';
}
