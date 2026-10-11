import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/map_models.dart';

/// Где в файле `.mbtiles` есть тайлы и на каких зумах. Границы взяты из
/// самих тайлов на самом глубоком зуме, а не из метаданных файла (там они
/// бывают неверными).
class MbtilesExtent {
  const MbtilesExtent({
    required this.minZoom,
    required this.maxZoom,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final int minZoom;
  final int maxZoom;
  final double west;
  final double south;
  final double east;
  final double north;

  static MbtilesExtent? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    double d(String key) => (map[key]! as num).toDouble();
    return MbtilesExtent(
      minZoom: (map['minZoom']! as num).toInt(),
      maxZoom: (map['maxZoom']! as num).toInt(),
      west: d('west'),
      south: d('south'),
      east: d('east'),
      north: d('north'),
    );
  }

  /// Пересекается ли с прямоугольником (градусы).
  bool intersects(GeoBox box) => west <= box.east && east >= box.west && south <= box.north && north >= box.south;
}

/// Прямоугольник в градусах.
class GeoBox {
  const GeoBox({required this.west, required this.south, required this.east, required this.north});

  final double west;
  final double south;
  final double east;
  final double north;

  /// Тот же прямоугольник, расширенный на [factor] своего размера в каждую
  /// сторону: экран и соседние участки вокруг него.
  GeoBox expanded(double factor) {
    final dx = (east - west) * factor;
    final dy = (north - south) * factor;
    return GeoBox(west: west - dx, south: south - dy, east: east + dx, north: north + dy);
  }
}

/// Чтение [MbtilesExtent] файла.
abstract class MbtilesExtentReader {
  Future<MbtilesExtent?> read(String path);
}

/// Читает через платформу (SQLite Android) и помнит ответ по пути: файл
/// читается один раз за запуск.
class PlatformMbtilesExtentReader implements MbtilesExtentReader {
  PlatformMbtilesExtentReader({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('sabyrmap/mbtiles');

  final MethodChannel _channel;
  final Map<String, Future<MbtilesExtent?>> _cache = {};

  @override
  Future<MbtilesExtent?> read(String path) => _cache.putIfAbsent(path, () async {
    try {
      return MbtilesExtent.fromMap(await _channel.invokeMapMethod<Object?, Object?>('info', {'path': path}));
    } catch (_) {
      // Не прочитали (повреждён, нет платформы) — границы неизвестны.
      return null;
    }
  });
}

final mbtilesExtentReaderProvider = Provider<MbtilesExtentReader>((ref) => PlatformMbtilesExtentReader());

/// Путь файла ортофотоплана из его источника (`mbtiles://<путь>`).
String? orthophotoPath(MapSource source) {
  final url = source.tileUrlTemplate;
  return url != null && url.startsWith('mbtiles://') ? url.substring('mbtiles://'.length) : null;
}

/// Сколько экранов вокруг видимого берётся «соседними»: ортофотоплан
/// включается чуть раньше, чем въезжает на экран.
const double orthophotoNeighbourFactor = 1.0;

/// Ортофотопланы, которые нужны для [viewport] на зуме [zoom]: те, что
/// попадают в экран и соседние участки, и не мельче своего первого зума
/// (на далёком зуме у файла нет тайлов). Файл с неизвестными границами
/// берётся всегда — лучше лишний, чем пропавший.
List<MapSource> orthophotosFor(
  List<MapSource> sources,
  Map<String, MbtilesExtent?> extents, {
  required GeoBox viewport,
  required double zoom,
}) {
  final area = viewport.expanded(orthophotoNeighbourFactor);
  bool needed(MbtilesExtent? extent) => extent == null || (extent.intersects(area) && zoom >= extent.minZoom - 1);
  return [
    for (final source in sources)
      if (needed(extents[source.id])) source,
  ];
}
