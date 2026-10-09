import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

import 'dem_coverage.dart';
import 'dem_descriptor.dart';
import 'dem_settings.dart';
import 'dem_tile.dart';

/// Данные высот из файлов `.hgt` в `<корень>/datastore/dem` (с подпапками).
///
/// Decision: настройки читаются и пишутся через [MapsSettings] (переданный
/// в конструктор [DemSettings] — начальное значение до [loadSettings]).
class DemManager {
  DemManager(this._paths, DemSettings settings, {MapsSettings? store}) : _settings = settings, _store = store;

  final StoragePaths _paths;
  final MapsSettings? _store;
  DemSettings _settings;

  /// Сколько тайлов держать в памяти.
  static const int cacheSize = 4;

  final Map<String, DemTile> _cache = {};
  List<DemDescriptor>? _index;

  static final RegExp _name = RegExp(r'^([NS])(\d{1,2})([EW])(\d{1,3})\.hgt$', caseSensitive: false);

  DemSettings get settings => _settings;

  Future<DemSettings> loadSettings() async {
    final store = _store;
    if (store != null) _settings = store.demSettings;
    return _settings;
  }

  Future<void> saveSettings(DemSettings s) async {
    _settings = s;
    await _store?.setDemSettings(s);
  }

  /// Файлы `.hgt` в [folder] и подпапках, с именем вида `N50E030.hgt` и
  /// размером квадратной сетки 16-битных чисел.
  Future<List<DemDescriptor>> scanFolder(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return const [];
    final out = <DemDescriptor>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final m = _name.firstMatch(p.basename(e.path));
      if (m == null) continue;
      final size = await e.length();
      final n = sqrt(size / 2).round();
      if (n < 2 || n * n * 2 != size) continue;
      final lat = int.parse(m[2]!) * (m[1]!.toUpperCase() == 'S' ? -1 : 1);
      final lon = int.parse(m[4]!) * (m[3]!.toUpperCase() == 'W' ? -1 : 1);
      out.add(
        DemDescriptor(path: e.path, tileX: lon, tileY: lat, samplesPerRow: n, isCustom: n != 1201 && n != 3601),
      );
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// Файл, покрывающий точку; нет — null.
  Future<DemDescriptor?> findTileFor(LandmarkLocation location) async {
    final want = DemCoverage.forLocation(location);
    final index = _index ??= await scanFolder(_paths.datastoreDem);
    return index.where((d) => d.tileX == want.tileX && d.tileY == want.tileY).firstOrNull;
  }

  /// Покрыта ли точка данными.
  Future<DemCoverage> coverageFor(LandmarkLocation location) async {
    final c = DemCoverage.forLocation(location);
    return DemCoverage(tileX: c.tileX, tileY: c.tileY, isCovered: await findTileFor(location) != null);
  }

  /// Читает тайл: 16-битные числа big-endian по строкам. Размер не тот или
  /// файл не читается — null.
  Future<DemTile?> loadTile(DemDescriptor descriptor) async {
    final cached = _cache.remove(descriptor.path);
    if (cached != null) return _cache[descriptor.path] = cached;
    final Uint8List bytes;
    try {
      bytes = await File(descriptor.path).readAsBytes();
    } on FileSystemException {
      return null;
    }
    final n = descriptor.samplesPerRow;
    if (bytes.length != n * n * 2) return null;
    final data = ByteData.sublistView(bytes);
    final values = Uint16List(n * n);
    for (var i = 0; i < values.length; i++) {
      values[i] = data.getUint16(i * 2);
    }
    final tile = DemTile(descriptor: descriptor, elevations: values);
    _cache[descriptor.path] = tile;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return tile;
  }

  /// Высота в точке (билинейно); данные выключены или их нет — null.
  Future<double?> elevationAt(LandmarkLocation location) async {
    if (!_settings.useElevationData) return null;
    final descriptor = await findTileFor(location);
    if (descriptor == null) return null;
    final tile = await loadTile(descriptor);
    return tile?.sample(location.longitude - descriptor.tileX, location.latitude - descriptor.tileY);
  }

  /// Забыть найденные файлы (после добавления новых).
  void invalidate() {
    _index = null;
    _cache.clear();
  }
}
