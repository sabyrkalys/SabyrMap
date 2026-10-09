import 'dart:io';

import 'package:app/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

import 'icon_info.dart';

/// Ищет файлы иконок в [StoragePaths.icons].
///
/// Пропускаются: симлинки, файлы больше [maxFileBytes], расширения не из
/// [supportedExtensions], папки глубже [maxDepth].
class IconResolver {
  IconResolver(this._paths);

  final StoragePaths _paths;

  /// Допустимые расширения, в порядке предпочтения.
  static const Set<String> supportedExtensions = {'svg', 'png', 'jpg', 'jpeg', 'gif', 'bmp'};

  /// Самый большой файл иконки, который берём: 100 КБ.
  static const int maxFileBytes = 100 * 1024;

  /// Сколько уровней подпапок обходить.
  static const int maxDepth = 3;

  /// Все иконки, по категории (сначала без категории), затем по имени.
  ///
  /// Decision: если у одного id несколько файлов (`tent.svg` и `tent.png`),
  /// берётся первый по порядку [supportedExtensions].
  Future<List<IconInfo>> scan() async {
    final root = Directory(_paths.icons);
    if (!await root.exists()) return const [];
    final byId = <String, IconInfo>{};
    await _walk(root, 0, byId);
    final icons = byId.values.toList()
      ..sort((a, b) {
        final byCategory = (a.category ?? '').compareTo(b.category ?? '');
        if (byCategory != 0) return byCategory;
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return icons;
  }

  /// Есть ли иконка с таким id.
  Future<bool> exists(String id) async => await resolve(id) != null;

  /// Абсолютный путь файла иконки по id или null.
  Future<String?> resolve(String id) async {
    if (!_isSafeId(id)) return null;
    for (final ext in supportedExtensions) {
      final path = '${p.joinAll([_paths.icons, ...id.split('/')])}.$ext';
      if (await _isUsableFile(path)) return path;
    }
    return null;
  }

  Future<void> _walk(Directory dir, int depth, Map<String, IconInfo> byId) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      if (entity is Directory) {
        if (depth < maxDepth) await _walk(entity, depth + 1, byId);
      } else if (entity is File) {
        final info = await _infoFor(entity);
        if (info == null) continue;
        final existing = byId[info.id];
        if (existing == null || _rank(info.extension) < _rank(existing.extension)) byId[info.id] = info;
      }
      // Link — пропускаем.
    }
  }

  Future<IconInfo?> _infoFor(File file) async {
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    if (!supportedExtensions.contains(ext)) return null;
    if (!await _isUsableFile(file.path)) return null;
    final relative = p.relative(file.path, from: _paths.icons);
    final segments = p.split(relative);
    final id = p.posix.joinAll([...segments.take(segments.length - 1), p.basenameWithoutExtension(file.path)]);
    return IconInfo(
      id: id,
      name: p.basenameWithoutExtension(file.path),
      category: segments.length > 1 ? segments.first : null,
      path: file.path,
      extension: ext,
    );
  }

  Future<bool> _isUsableFile(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) return false;
    try {
      return await File(path).length() <= maxFileBytes;
    } on FileSystemException {
      return false;
    }
  }

  static int _rank(String ext) => supportedExtensions.toList().indexOf(ext);

  /// id без выхода из папки иконок и без пустых сегментов.
  static bool _isSafeId(String id) {
    if (id.isEmpty || id.startsWith('/') || id.contains(r'\')) return false;
    return id.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
  }
}
