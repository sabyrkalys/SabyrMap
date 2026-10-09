import 'package:app/maps/file_maps/map_bounds.dart';

/// Картинка, привязанная к местности (KML GroundOverlay).
class KmlOverlayDescriptor {
  const KmlOverlayDescriptor({
    required this.name,
    required this.imagePath,
    required this.bounds,
    this.rotation = 0,
    this.drawOrder,
  });

  final String name;

  /// Абсолютный путь к изображению на диске.
  final String imagePath;
  final MapBounds bounds;

  /// Поворот, градусы против часовой.
  final double rotation;
  final int? drawOrder;
}
