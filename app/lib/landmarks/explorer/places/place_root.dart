/// Вид корневого раздела проводника.
enum PlaceRootKind { landmarks, downloads, deviceFolder, custom }

/// Корневой раздел в левом меню проводника.
class PlaceRoot {
  const PlaceRoot({required this.id, required this.title, required this.path, required this.kind});

  final String id;
  final String title;

  /// Абсолютный путь папки раздела.
  final String path;
  final PlaceRootKind kind;

  @override
  bool operator ==(Object other) =>
      other is PlaceRoot && other.id == id && other.title == title && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, title, path, kind);

  @override
  String toString() => 'PlaceRoot($id, $path)';
}
