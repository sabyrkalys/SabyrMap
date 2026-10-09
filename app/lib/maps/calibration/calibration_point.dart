/// Привязка точки изображения к месту на Земле.
class CalibrationPoint {
  const CalibrationPoint({required this.imageX, required this.imageY, required this.worldLon, required this.worldLat});

  /// Пиксели изображения.
  final double imageX;
  final double imageY;

  /// Градусы WGS84.
  final double worldLon;
  final double worldLat;

  CalibrationPoint copyWith({double? imageX, double? imageY, double? worldLon, double? worldLat}) => CalibrationPoint(
    imageX: imageX ?? this.imageX,
    imageY: imageY ?? this.imageY,
    worldLon: worldLon ?? this.worldLon,
    worldLat: worldLat ?? this.worldLat,
  );

  Map<String, Object?> toJson() => {'x': imageX, 'y': imageY, 'lon': worldLon, 'lat': worldLat};

  factory CalibrationPoint.fromJson(Map<String, dynamic> json) => CalibrationPoint(
    imageX: (json['x'] as num).toDouble(),
    imageY: (json['y'] as num).toDouble(),
    worldLon: (json['lon'] as num).toDouble(),
    worldLat: (json['lat'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is CalibrationPoint &&
      other.imageX == imageX &&
      other.imageY == imageY &&
      other.worldLon == worldLon &&
      other.worldLat == worldLat;

  @override
  int get hashCode => Object.hash(imageX, imageY, worldLon, worldLat);
}
