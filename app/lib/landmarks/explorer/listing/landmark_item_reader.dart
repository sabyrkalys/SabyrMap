import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/serialization/binary_reader.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:app/landmarks/serialization/metadata_codec.dart';
import 'package:app/storage/storage_service.dart';
import 'package:path/path.dart' as p;

import 'landmark_item.dart';

/// Читает из файлов меток только то, что нужно списку: заголовок,
/// метаданные и (у путевой точки) координату. Остальное содержимое не
/// читается и не разбирается.
///
/// Decision: заголовок — формат Спринта 1 (`int (magic << 8) | version`,
/// `int headerSize`), а не отдельные поля с текстовой сигнатурой: файлы
/// sabyrmap уже пишутся так, и [LandmarkCodec.readHeader] его проверяет.
class LandmarkItemReader {
  LandmarkItemReader(this._service);

  final StorageService _service;

  /// Сколько файлов читается одновременно.
  static const int maxParallelReads = 8;

  /// Сколько байт читается сначала; если метаданные длиннее — больше.
  static const int initialChunkBytes = 4096;

  /// Элемент списка для файла [path]; null — файл не метка sabyrmap,
  /// обрезан или повреждён (такие пропускаются молча, с записью в лог).
  Future<LandmarkItem?> read(String path) => _readHeader(path);

  /// Элементы для всех файлов меток в [directory] (не рекурсивно, без
  /// симлинков), в порядке путей. Нечитаемые пропускаются.
  Future<List<LandmarkItem>> readAll(String directory, {Set<String>? extensions}) async {
    final files = await _service.listFiles(directory, extensions: extensions ?? LandmarkType.extensions);
    final items = <LandmarkItem>[];
    for (var start = 0; start < files.length; start += maxParallelReads) {
      final chunk = files.sublist(start, min(start + maxParallelReads, files.length));
      final read = await Future.wait(chunk.map((f) => _readHeader(f.path)));
      items.addAll(read.whereType<LandmarkItem>());
    }
    return items;
  }

  Future<LandmarkItem?> _readHeader(String path) async {
    final file = File(path);
    RandomAccessFile? raf;
    try {
      if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) return null;
      final stat = await file.stat();
      raf = await file.open();
      final length = stat.size;
      var chunk = min(initialChunkBytes, length);
      while (true) {
        await raf.setPosition(0);
        final bytes = await raf.read(chunk);
        try {
          return _parse(path, bytes, stat);
        } on SerializationException {
          // Метаданные не поместились в прочитанный кусок — читаем больше;
          // если файл прочитан целиком, он повреждён.
          if (chunk >= length) rethrow;
          chunk = min(chunk * 4, length);
        }
      }
    } on SerializationException catch (e) {
      developer.log('Skipping unreadable landmark file $path: $e', name: 'sabyrmap.explorer');
      return null;
    } on FileSystemException catch (e) {
      developer.log('Cannot read landmark file $path: $e', name: 'sabyrmap.explorer');
      return null;
    } finally {
      await raf?.close();
    }
  }

  static LandmarkItem _parse(String path, Uint8List bytes, FileStat stat) {
    final r = BinaryReader(bytes);
    final header = LandmarkCodec.readHeader(r);
    final technical = MetadataCodec.read(r);
    final user = MetadataCodec.read(r);

    double? latitude;
    double? longitude;
    if (header.type == LandmarkType.waypoint) {
      // Location: int size, int lon·1e7, int lat·1e7 — остальное не нужно.
      final sizeAt = r.position;
      final size = r.readInt();
      if (size < 8) throw SerializationException('Invalid location size $size', position: sizeAt);
      longitude = r.readInt() / 1e7;
      latitude = r.readInt() / 1e7;
    }

    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final createdAt = user.createdAtMs ?? technical.createdAtMs ?? modifiedMs;
    final name = user.name;
    return LandmarkItem(
      path: path,
      name: name != null && name.trim().isNotEmpty
          ? name
          : FileNaming.baseFromName(p.basenameWithoutExtension(path)),
      type: header.type,
      colorValue: user.colorValue ?? LandmarkItem.defaultColor,
      iconId: user.iconId,
      createdAt: createdAt,
      updatedAt: user.updatedAtMs ?? technical.updatedAtMs ?? createdAt,
      fileSizeBytes: stat.size,
      fileModifiedAt: stat.modified,
      latitude: latitude,
      longitude: longitude,
      lengthMeters: _number(user, LandmarkMetadata.lengthKey),
      durationMs: _int(user, LandmarkMetadata.durationKey),
      elevationGainMeters: _number(user, LandmarkMetadata.elevationGainKey),
      elevationLossMeters: _number(user, LandmarkMetadata.elevationLossKey),
      areaSquareMeters: _number(user, LandmarkMetadata.areaKey),
      activity: _string(user, LandmarkMetadata.activityKey),
      year: _int(user, LandmarkMetadata.yearKey),
    );
  }

  static double? _number(LandmarkMetadata m, String key) => switch (m.entries[key]) {
    final num v => v.toDouble(),
    _ => null,
  };

  static int? _int(LandmarkMetadata m, String key) => switch (m.entries[key]) {
    final int v => v,
    _ => null,
  };

  static String? _string(LandmarkMetadata m, String key) => switch (m.entries[key]) {
    final String v when v.isNotEmpty => v,
    _ => null,
  };
}
