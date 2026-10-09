/// Откуда брать высоты при импорте (и писать ли их при экспорте).
enum ElevationSource {
  /// Высоты не читаются и не пишутся.
  none,

  /// Высоты над эллипсоидом WGS84 — как есть.
  wgs84,

  /// Высоты над геоидом EGM96. Пересчёт пока не делается: значения
  /// сохраняются как WGS84, с предупреждением.
  egm96;

  /// Читать ли высоты вообще.
  bool get readsElevation => this != none;

  /// Предупреждение для этого источника, если есть.
  String? get warning =>
      this == egm96 ? 'EGM96 heights are not converted yet; they are stored as WGS84 heights' : null;

  /// Из строки опции; неизвестная — [wgs84].
  static ElevationSource parse(Object? value) => switch (value) {
    final ElevationSource s => s,
    final String s => values.where((v) => v.name == s.toLowerCase()).firstOrNull ?? wgs84,
    _ => wgs84,
  };
}
