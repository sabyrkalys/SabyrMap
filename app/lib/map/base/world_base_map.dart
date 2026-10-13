import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Встроенная базовая карта мира (Natural Earth, z0–5): лежит в APK и
/// копируется в папку приложения, откуда её открывает MapLibre.
class WorldBaseMap {
  WorldBaseMap({AssetBundle? bundle, required this.directory}) : _bundle = bundle ?? rootBundle;

  static const String asset = 'assets/base/world.mbtiles';
  static const String fileName = 'world.mbtiles';

  /// Её свойства для «Деталей».
  static const String name = 'Natural Earth';
  static const int minZoom = 0;
  static const int maxZoom = 5;

  final AssetBundle _bundle;
  final Future<Directory> Function() directory;

  /// Путь к файлу; копирует, если его нет или он от другой версии APK.
  Future<String> install() async {
    final file = File('${(await directory()).path}/$fileName');
    final data = await _bundle.load(asset);
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return file.path;
  }
}

/// Путь к базовой карте; null — недоступна (тесты, нет места).
final worldBaseMapPathProvider = FutureProvider<String?>((ref) async {
  try {
    return await WorldBaseMap(
      directory: () async => Directory('${(await getApplicationSupportDirectory()).path}/base'),
    ).install();
  } on Object {
    return null;
  }
});
