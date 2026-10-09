import 'package:app/landmarks/import_export/utils/elevation_source.dart';

/// Опции импорта.
class ImportOptions {
  const ImportOptions({
    this.folder,
    this.elevation = ElevationSource.wgs84,
    this.charset,
    this.fixGpsWeekRollover = false,
    this.extras = const {},
  });

  /// Папка для созданных файлов; null — из запроса или по умолчанию.
  final String? folder;
  final ElevationSource elevation;

  /// Кодировка текста; null — определить автоматически.
  final String? charset;

  /// Исправлять даты приёмников с переполнением номера недели GPS.
  final bool fixGpsWeekRollover;

  /// Опции конкретного формата (id из схемы → значение).
  final Map<String, Object?> extras;

  ImportOptions copyWith({
    String? folder,
    ElevationSource? elevation,
    String? charset,
    bool? fixGpsWeekRollover,
    Map<String, Object?>? extras,
  }) => ImportOptions(
    folder: folder ?? this.folder,
    elevation: elevation ?? this.elevation,
    charset: charset ?? this.charset,
    fixGpsWeekRollover: fixGpsWeekRollover ?? this.fixGpsWeekRollover,
    extras: extras ?? this.extras,
  );

  /// Опция формата [id] типа [T] или [fallback].
  T extra<T>(String id, T fallback) => switch (extras[id]) {
    final T v => v,
    _ => fallback,
  };

  /// 1024 недели — шаг переполнения номера недели GPS.
  static const int gpsRolloverMs = 1024 * 7 * 24 * 3600 * 1000;

  /// Время ранее этого считается сдвинутым на 1024 недели.
  static final int _rolloverThresholdMs = DateTime.utc(2000).millisecondsSinceEpoch;

  /// Время точки с поправкой [fixGpsWeekRollover].
  ///
  /// Decision: время раньше 2000 года считается сдвинутым на 1024 недели
  /// назад (типичная ошибка старых приёмников) и сдвигается вперёд.
  int fixTime(int ms) => fixGpsWeekRollover && ms < _rolloverThresholdMs ? ms + gpsRolloverMs : ms;
}
