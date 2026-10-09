import 'dart:convert';
import 'dart:io';

import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:path/path.dart' as p;

/// Оценка размера резервной копии (до сжатия).
abstract final class SizeEstimator {
  /// Файлы меток в [folder] с подпапками.
  static Future<int> estimateLandmarks(String folder) => _sum(
    folder,
    (path) => LandmarkType.fromExtension(p.extension(path)) != null,
  );

  /// Все файлы в [folder] с подпапками (без симлинков).
  static Future<int> estimateFolder(String folder) => _sum(folder, (_) => true);

  /// Размер `settings.json`.
  static Future<int> estimateSettings(AppSettings settings) async => utf8.encode(encodeSettings(settings.exportAll())).length;

  /// Число файлов в [folder] с подпапками.
  static Future<int> countFiles(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) n++;
    }
    return n;
  }

  /// Настройки как JSON для архива.
  static String encodeSettings(Map<String, Object> values) => const JsonEncoder.withIndent('  ').convert(values);

  static Future<int> _sum(String folder, bool Function(String path) include) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && include(e.path)) total += await e.length();
    }
    return total;
  }
}
