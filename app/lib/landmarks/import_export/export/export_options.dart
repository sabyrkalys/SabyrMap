/// Опции экспорта.
class ExportOptions {
  const ExportOptions({this.includeWaypoints = true, this.includeSegments = true, this.charset, this.extras = const {}});

  /// Писать путевые точки трека.
  final bool includeWaypoints;

  /// Сохранять деление трека на сегменты; нет — все точки одним куском.
  final bool includeSegments;

  /// Кодировка текстовых форматов; null — utf-8. XML-форматы всегда в utf-8.
  final String? charset;

  /// Опции конкретного формата (id из схемы → значение).
  final Map<String, Object?> extras;

  ExportOptions copyWith({bool? includeWaypoints, bool? includeSegments, String? charset, Map<String, Object?>? extras}) =>
      ExportOptions(
        includeWaypoints: includeWaypoints ?? this.includeWaypoints,
        includeSegments: includeSegments ?? this.includeSegments,
        charset: charset ?? this.charset,
        extras: extras ?? this.extras,
      );

  /// Опция формата [id] типа [T] или [fallback].
  T extra<T>(String id, T fallback) => switch (extras[id]) {
    final T v => v,
    _ => fallback,
  };
}
