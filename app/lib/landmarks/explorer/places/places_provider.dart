import 'dart:io';

import 'package:app/storage/storage_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'place_root.dart';

/// Поиск папки; null — папки нет на этой платформе.
typedef DirectoryLookup = Future<String?> Function();

/// Корневые разделы проводника: «Метки», «Загрузки», «Устройство».
class PlacesProvider {
  PlacesProvider(this._paths, {@visibleForTesting DirectoryLookup? downloads, @visibleForTesting DirectoryLookup? device})
    : _downloads = downloads ?? _systemDownloads,
      _device = device ?? _externalStorage;

  final StoragePaths _paths;
  final DirectoryLookup _downloads;
  final DirectoryLookup _device;

  /// Общая папка загрузок Android.
  static const String androidDownloads = '/storage/emulated/0/Download';

  /// Разделы в порядке меню. Несуществующие папки и повторы по пути
  /// пропускаются.
  Future<List<PlaceRoot>> listPlaces() async {
    final candidates = [
      PlaceRoot(id: 'landmarks', title: 'Метки', path: _paths.landmarks, kind: PlaceRootKind.landmarks),
      if (await _safe(_downloads) case final path?)
        PlaceRoot(id: 'downloads', title: 'Загрузки', path: path, kind: PlaceRootKind.downloads),
      if (await _safe(_device) case final path?)
        PlaceRoot(id: 'device', title: 'Устройство', path: path, kind: PlaceRootKind.deviceFolder),
    ];
    final seen = <String>{};
    final places = <PlaceRoot>[];
    for (final place in candidates) {
      final key = p.normalize(place.path);
      if (!seen.add(key)) continue;
      if (!await Directory(place.path).exists()) continue;
      places.add(place);
    }
    return places;
  }

  static Future<String?> _safe(DirectoryLookup lookup) async {
    try {
      return await lookup();
    } catch (_) {
      return null;
    }
  }

  /// Decision: «Загрузки» — общая папка Download, если она есть (Android);
  /// иначе папка загрузок, которую даёт система.
  static Future<String?> _systemDownloads() async {
    if (Platform.isAndroid && await Directory(androidDownloads).exists()) return androidDownloads;
    return (await getDownloadsDirectory())?.path;
  }

  static Future<String?> _externalStorage() async => (await getExternalStorageDirectory())?.path;
}
