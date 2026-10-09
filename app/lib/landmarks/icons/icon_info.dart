/// Файл иконки из папки иконок sabyrmap.
class IconInfo {
  const IconInfo({required this.id, required this.name, required this.path, required this.extension, this.category});

  /// Путь внутри папки иконок без расширения, через `/`: `tourism/tent`.
  final String id;

  /// Последний сегмент [id]: `tent`.
  final String name;

  /// Подпапка первого уровня (`tourism`); null — иконка в корне папки.
  final String? category;

  /// Абсолютный путь к файлу.
  final String path;

  /// Расширение без точки, в нижнем регистре: svg, png, jpg, jpeg, gif, bmp.
  final String extension;

  @override
  bool operator ==(Object other) =>
      other is IconInfo &&
      other.id == id &&
      other.name == name &&
      other.category == category &&
      other.path == path &&
      other.extension == extension;

  @override
  int get hashCode => Object.hash(id, name, category, path, extension);

  @override
  String toString() => 'IconInfo($id.$extension)';
}
