import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Все метки папки меток в памяти — один источник для карты, «Всех меток»
/// и «Меток на экране». Запись — [LandmarkItem]: файл метки, а у файла
/// меток (`.ldk`) ещё и каждый объект внутри ([LandmarkItem.nestedPath]).
///
/// Диск обходится один раз ([rebuild]); дальше индекс узнаёт об
/// изменениях от [refresh] — его зовёт репозиторий после каждой записи,
/// а наблюдатель — после правок извне.
///
/// Decision: операции выполняются строго по очереди — точечное обновление,
/// пришедшее во время перестройки, применяется после неё, а не теряется.
class LandmarkIndex extends ChangeNotifier {
  LandmarkIndex(String root, this._reader) : root = p.normalize(root);

  /// Папка меток.
  final String root;
  final LandmarkItemReader _reader;

  final Map<String, LandmarkItem> _items = {};
  Future<void> _queue = Future.value();
  bool _ready = false;

  /// Сколько файлов читается одновременно.
  static const int maxParallelReads = 8;

  /// Первая перестройка завершена.
  bool get isReady => _ready;

  /// Все записи (файлы и объекты внутри `.ldk`).
  Iterable<LandmarkItem> get items => _items.values;

  LandmarkItem? byPath(String path) => _items[p.normalize(path)];

  /// Записи типа [type]; [nested] — с объектами внутри файлов меток.
  List<LandmarkItem> byType(LandmarkType type, {bool nested = true}) => [
    for (final item in _items.values)
      if (item.type == type && (nested || !item.isNested)) item,
  ];

  /// Файлы меток в папке [folder]; [recursive] — с подпапками. Объекты
  /// внутри `.ldk` сюда не входят ([nestedIn]).
  List<LandmarkItem> inFolder(String folder, {bool recursive = false}) {
    final dir = p.normalize(folder);
    return [
      for (final item in _items.values)
        if (!item.isNested && (recursive ? p.isWithin(dir, item.path) : p.equals(p.dirname(item.path), dir))) item,
    ];
  }

  /// Объекты внутри файла меток [ldkPath], по порядку.
  List<LandmarkItem> nestedIn(String ldkPath) {
    final file = p.normalize(ldkPath);
    return [
      for (final item in _items.values)
        if (item.isNested && item.filePath == file) item,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Обходит папку меток заново.
  Future<void> rebuild() => _serial(() async {
    final fresh = <String, LandmarkItem>{};
    for (final item in await _readUnder(root)) {
      fresh[item.path] = item;
    }
    _items
      ..clear()
      ..addAll(fresh);
    _ready = true;
    notifyListeners();
  });

  /// Перечитывает [paths]: файл — заново (вместе с объектами внутри
  /// `.ldk`), папку — со всем содержимым; исчезнувшее убирается. Пути
  /// вне [root] не трогаются.
  Future<void> refresh(Iterable<String> paths) {
    final targets = {
      for (final path in paths)
        if (_underRoot(p.normalize(path))) p.normalize(path),
    };
    if (targets.isEmpty) return _queue;
    return _serial(() async {
      for (final target in targets) {
        // Сначала читается, потом подменяется: пока файл читается, его
        // прежняя запись остаётся в индексе.
        final kind = await FileSystemEntity.type(target, followLinks: false);
        final fresh = switch (kind) {
          FileSystemEntityType.directory => await _readUnder(target),
          FileSystemEntityType.file => await _readFile(target),
          _ => const <LandmarkItem>[],
        };
        _items.removeWhere((key, item) {
          final file = item.filePath;
          return file == target || p.isWithin(target, file);
        });
        for (final item in fresh) {
          _items[item.path] = item;
        }
      }
      notifyListeners();
    });
  }

  bool _underRoot(String path) => p.equals(path, root) || p.isWithin(root, path);

  /// Знает ли индекс содержимое [folder] (папка меток или внутри неё).
  bool covers(String folder) => _ready && _underRoot(p.normalize(folder));

  Future<List<LandmarkItem>> _readUnder(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return const [];
    final files = <String>[
      await for (final entity in dir.list(recursive: true, followLinks: false))
        if (entity is File && LandmarkType.fromExtension(p.extension(entity.path)) != null) p.normalize(entity.path),
    ];
    final out = <LandmarkItem>[];
    for (var start = 0; start < files.length; start += maxParallelReads) {
      final chunk = files.sublist(start, min(start + maxParallelReads, files.length));
      for (final items in await Future.wait(chunk.map(_readFile))) {
        out.addAll(items);
      }
    }
    return out;
  }

  /// Файл и (у `.ldk`) объекты внутри; нечитаемый — пусто.
  Future<List<LandmarkItem>> _readFile(String path) async {
    final type = LandmarkType.fromExtension(p.extension(path));
    if (type == null) return const [];
    final item = await _reader.read(path);
    if (item == null) return const [];
    return [item, if (type == LandmarkType.ldkFile) ...await _reader.readNested(path)];
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }
}
