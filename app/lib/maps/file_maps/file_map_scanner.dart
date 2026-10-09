import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/maps/registry/map_format_capability.dart';
import 'package:app/maps/registry/map_source_registry.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'file_map_descriptor.dart';
import 'file_map_metadata.dart';
import 'map_bounds.dart';

/// Поиск файловых карт и чтение их метаданных (тайлы не читаются).
///
/// Decision — откуда берутся границы и зумы:
/// - файл-спутник `<карта>.bounds` (JSON: north, south, west, east,
///   необязательно minZoom, maxZoom, tileSize, name) — для любого формата;
///   его же пишет [ImageOverlayInstaller];
/// - ZIP с тайлами `z/x/y.ext` — по именам тайлов;
/// - KML/KMZ — по `LatLonBox` первого `GroundOverlay`.
/// Прочие форматы (AQM, PGD, GPKG, MBTiles, SQLiteDB, QCT, RMAP, TIFF...)
/// без спутника дают метаданные без границ: их внутреннее устройство здесь
/// не разбирается (часть из них — SQLite, а пакета SQLite в стеке нет).
class FileMapScanner {
  FileMapScanner(this._paths, {MapSourceRegistry? registry})
    : _registry = registry ?? MapSourceRegistry.buildDefault();

  final StoragePaths _paths;
  final MapSourceRegistry _registry;
  List<FileMapDescriptor> _known = const [];

  /// Расширение файла-спутника с границами.
  static const String boundsExtension = '.bounds';

  /// Карты, найденные последним [scanAll].
  List<FileMapDescriptor> get known => _known;

  /// Растровые карты в [folder] (без подпапок), по имени файла.
  Future<List<FileMapDescriptor>> scanFolder(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return const [];
    final out = <FileMapDescriptor>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final metadata = await readMetadata(entity.path);
      if (metadata == null) continue;
      out.add(FileMapDescriptor(metadata: metadata, displayPath: _display(entity.path)));
    }
    out.sort((a, b) => a.metadata.path.compareTo(b.metadata.path));
    return out;
  }

  /// Метаданные файла растровой карты; не карта или не растр — null.
  Future<FileMapMetadata?> readMetadata(String path) async {
    final format = _registry.byExtension(p.extension(path));
    if (format == null || !format.has(MapFormatCapability.raster)) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = await file.stat();

    var bounds = <String, Object?>{};
    final sidecar = File('$path$boundsExtension');
    if (await sidecar.exists()) {
      bounds = _readSidecar(await sidecar.readAsString());
    } else if (format.id == 'zip-xyz') {
      bounds = _zipTiles(await file.readAsBytes());
    } else if (format.id == 'kml-overlay') {
      bounds = _kmlBox(await file.readAsBytes());
    }
    return FileMapMetadata(
      path: path,
      displayName: bounds['name'] as String? ?? p.basenameWithoutExtension(path),
      sourceFormatId: format.id,
      bounds: bounds['bounds'] as MapBounds?,
      minZoom: bounds['minZoom'] as int?,
      maxZoom: bounds['maxZoom'] as int?,
      tileSize: bounds['tileSize'] as int?,
      fileSizeBytes: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
    );
  }

  /// Карты в `<корень>/maps` и `<корень>/datastore/maps`.
  Future<List<FileMapDescriptor>> scanAll() async {
    _known = List.unmodifiable([
      ...await scanFolder(_paths.maps),
      ...await scanFolder(_paths.datastoreMaps),
    ]);
    return _known;
  }

  String _display(String path) =>
      p.isWithin(_paths.appRoot, path) ? p.relative(path, from: _paths.appRoot) : path;

  static Map<String, Object?> _readSidecar(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return {
        'bounds': MapBounds.fromJson(json),
        'minZoom': json['minZoom'] as int?,
        'maxZoom': json['maxZoom'] as int?,
        'tileSize': json['tileSize'] as int?,
        'name': json['name'] as String?,
      };
    } on Object {
      return const {};
    }
  }

  /// Зумы и границы по тайлам `z/x/y.ext` (схема XYZ) на наибольшем зуме.
  static Map<String, Object?> _zipTiles(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return const {};
    }
    final pattern = RegExp(r'(?:^|/)(\d{1,2})/(\d+)/(\d+)\.\w+$');
    final tiles = <(int, int, int)>[];
    for (final f in archive.files) {
      final m = pattern.firstMatch(f.name);
      if (f.isFile && m != null) tiles.add((int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
    }
    if (tiles.isEmpty) return const {};
    final maxZoom = tiles.map((t) => t.$1).reduce(max);
    final top = tiles.where((t) => t.$1 == maxZoom);
    final minX = top.map((t) => t.$2).reduce(min);
    final maxX = top.map((t) => t.$2).reduce(max);
    final minY = top.map((t) => t.$3).reduce(min);
    final maxY = top.map((t) => t.$3).reduce(max);
    return {
      'bounds': MapBounds(
        northLat: tileLat(minY, maxZoom),
        southLat: tileLat(maxY + 1, maxZoom),
        westLon: tileLon(minX, maxZoom),
        eastLon: tileLon(maxX + 1, maxZoom),
      ),
      'minZoom': tiles.map((t) => t.$1).reduce(min),
      'maxZoom': maxZoom,
    };
  }

  static Map<String, Object?> _kmlBox(Uint8List bytes) {
    try {
      var data = bytes;
      if (bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        final kml = archive.findFile('doc.kml') ??
            archive.files.where((f) => f.name.toLowerCase().endsWith('.kml')).firstOrNull;
        if (kml == null) return const {};
        data = kml.content;
      }
      final doc = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
      final box = doc.descendantElements.where((e) => e.localName == 'LatLonBox').firstOrNull;
      if (box == null) return const {};
      double read(String name) => double.parse(box.childElements.firstWhere((e) => e.localName == name).innerText.trim());
      final name = doc.descendantElements.where((e) => e.localName == 'GroundOverlay').firstOrNull
          ?.childElements.where((e) => e.localName == 'name').firstOrNull?.innerText.trim();
      return {
        'bounds': MapBounds(northLat: read('north'), southLat: read('south'), westLon: read('west'), eastLon: read('east')),
        'name': name == null || name.isEmpty ? null : name,
      };
    } on Object {
      return const {};
    }
  }

  /// Долгота западного края тайла x на зуме z (Web Mercator).
  static double tileLon(int x, int z) => x / (1 << z) * 360 - 180;

  /// Широта северного края тайла y на зуме z (Web Mercator).
  static double tileLat(int y, int z) {
    final n = pi - 2 * pi * y / (1 << z);
    return 180 / pi * atan(0.5 * (exp(n) - exp(-n)));
  }
}
