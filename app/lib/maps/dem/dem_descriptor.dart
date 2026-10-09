/// Файл высот на диске.
class DemDescriptor {
  const DemDescriptor({
    required this.path,
    required this.tileX,
    required this.tileY,
    required this.samplesPerRow,
    this.isCustom = false,
  });

  final String path;

  /// Долгота и широта юго-западного угла.
  final int tileX;
  final int tileY;

  /// Точек в строке: 1201 (3″) или 3601 (1″).
  final int samplesPerRow;

  /// Нестандартный размер сетки.
  final bool isCustom;
}
