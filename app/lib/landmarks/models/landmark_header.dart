import 'landmark_type.dart';

/// Заголовок файла метки: тип, версия формата и размер заголовка.
///
/// В файле: `int magicWithVersion`, `int headerSize`.
class LandmarkHeader {
  const LandmarkHeader({required this.type, this.version = LandmarkType.formatVersion, this.headerSize = byteSize});

  /// Размер заголовка, который пишет sabyrmap: два int.
  static const int byteSize = 8;

  final LandmarkType type;
  final int version;

  /// Размер заголовка в байтах, включая оба поля.
  final int headerSize;

  /// Decision: сигнатура в старших 24 битах, версия — в младших 8:
  /// `(magic << 8) | version`. Порядок выбран по описанию задачи; исходной
  /// спецификации под рукой не было.
  int get magicWithVersion => (type.magic << 8) | (version & 0xFF);

  /// Сигнатура из упакованного значения.
  static int magicOf(int magicWithVersion) => (magicWithVersion >> 8) & 0xFFFFFF;

  /// Версия из упакованного значения.
  static int versionOf(int magicWithVersion) => magicWithVersion & 0xFF;

  @override
  bool operator ==(Object other) =>
      other is LandmarkHeader && other.type == type && other.version == version && other.headerSize == headerSize;

  @override
  int get hashCode => Object.hash(type, version, headerSize);
}
