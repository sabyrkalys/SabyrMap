import 'package:app/landmarks/models/landmark_location.dart';

/// Тайл высот 1°×1° (сетка по юго-западному углу) и есть ли он.
class DemCoverage {
  const DemCoverage({required this.tileX, required this.tileY, this.isCovered = false});

  /// Тайл с точкой: X — долгота угла, Y — широта угла.
  static DemCoverage forLocation(LandmarkLocation location) =>
      DemCoverage(tileX: location.longitude.floor(), tileY: location.latitude.floor());

  final int tileX;
  final int tileY;
  final bool isCovered;

  /// Имя файла тайла: `N50E030.hgt`.
  String get fileName {
    final ns = tileY < 0 ? 'S' : 'N';
    final ew = tileX < 0 ? 'W' : 'E';
    return '$ns${tileY.abs().toString().padLeft(2, '0')}$ew${tileX.abs().toString().padLeft(3, '0')}.hgt';
  }

  @override
  bool operator ==(Object other) =>
      other is DemCoverage && other.tileX == tileX && other.tileY == tileY && other.isCovered == isCovered;

  @override
  int get hashCode => Object.hash(tileX, tileY, isCovered);
}
