/// Тип файла метки: расширение и сигнатура (magic) в заголовке.
enum LandmarkType {
  waypoint(extension: 'wpt', magic: 0x50500A),
  set(extension: 'set', magic: 0x50500B),
  route(extension: 'rte', magic: 0x50500C),
  area(extension: 'are', magic: 0x50500D),
  track(extension: 'trk', magic: 0x50500E),

  /// Файл меток: контейнер для объектов разных типов. Единственный
  /// формат, который создаётся из UI; прочие форматы — импорт и экспорт.
  ldkFile(extension: 'ldk', magic: 0x50500F);

  const LandmarkType({required this.extension, required this.magic});

  /// Расширение файла без точки, в нижнем регистре.
  final String extension;

  /// 24-битная сигнатура типа в заголовке файла.
  final int magic;

  /// Версия формата, которую пишет и понимает sabyrmap (одна на все типы).
  static const int formatVersion = 1;

  /// Расширения всех типов, без точки.
  static Set<String> get extensions => {for (final t in values) t.extension};

  /// Тип по расширению: с точкой или без, без учёта регистра.
  static LandmarkType? fromExtension(String ext) {
    final normalized = (ext.startsWith('.') ? ext.substring(1) : ext).toLowerCase();
    for (final t in values) {
      if (t.extension == normalized) return t;
    }
    return null;
  }

  /// Тип по сигнатуре.
  static LandmarkType? fromMagic(int magic) {
    for (final t in values) {
      if (t.magic == magic) return t;
    }
    return null;
  }
}
