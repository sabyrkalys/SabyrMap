/// Проекция онлайн-карты. Поддерживается Web Mercator (EPSG:3857);
/// WKT и смещения хранятся на будущее.
class ProjectionSpec {
  const ProjectionSpec({
    this.code = webMercator,
    this.bboxCrsCode,
    this.wktDefinition,
    this.resolution,
    this.offsetX,
    this.offsetY,
    this.tileSize,
  });

  static const String webMercator = 'EPSG:3857';

  final String code;
  final String? bboxCrsCode;
  final String? wktDefinition;
  final double? resolution;
  final double? offsetX;
  final double? offsetY;
  final int? tileSize;

  ProjectionSpec copyWith({
    String? code,
    String? bboxCrsCode,
    String? wktDefinition,
    double? resolution,
    double? offsetX,
    double? offsetY,
    int? tileSize,
  }) => ProjectionSpec(
    code: code ?? this.code,
    bboxCrsCode: bboxCrsCode ?? this.bboxCrsCode,
    wktDefinition: wktDefinition ?? this.wktDefinition,
    resolution: resolution ?? this.resolution,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
    tileSize: tileSize ?? this.tileSize,
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'bboxCrs': bboxCrsCode,
    'wkt': wktDefinition,
    'resolution': resolution,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'tileSize': tileSize,
  };

  factory ProjectionSpec.fromJson(Map<String, dynamic> json) => ProjectionSpec(
    code: json['code'] as String? ?? webMercator,
    bboxCrsCode: json['bboxCrs'] as String?,
    wktDefinition: json['wkt'] as String?,
    resolution: (json['resolution'] as num?)?.toDouble(),
    offsetX: (json['offsetX'] as num?)?.toDouble(),
    offsetY: (json['offsetY'] as num?)?.toDouble(),
    tileSize: json['tileSize'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is ProjectionSpec &&
      other.code == code &&
      other.bboxCrsCode == bboxCrsCode &&
      other.wktDefinition == wktDefinition &&
      other.resolution == resolution &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.tileSize == tileSize;

  @override
  int get hashCode => Object.hash(code, bboxCrsCode, wktDefinition, resolution, offsetX, offsetY, tileSize);
}
