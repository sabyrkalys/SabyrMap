import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'bookmark.dart';
import 'bookmark_store.dart';

/// Закладки проводника: список, добавление, удаление, переименование и
/// перенос вслед за папками. Каждое изменение сохраняется и сообщается
/// слушателям.
class BookmarkController extends ChangeNotifier {
  BookmarkController(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final BookmarkStore _store;
  final DateTime Function() _clock;
  List<Bookmark> _bookmarks = const [];

  /// По порядку добавления.
  List<Bookmark> get bookmarks => _bookmarks;
  bool get isEmpty => _bookmarks.isEmpty;

  /// Закладка на папку [path], если есть.
  Bookmark? byPath(String path) => _bookmarks.where((b) => p.equals(b.path, path)).firstOrNull;

  Future<void> load() async {
    _bookmarks = List.unmodifiable(await _store.loadAll());
    notifyListeners();
  }

  /// Добавляет закладку; та же папка уже в закладках — ничего.
  Future<void> add(Bookmark bookmark) async {
    if (byPath(bookmark.path) != null) return;
    await _set([..._bookmarks, bookmark]);
  }

  /// Закладка на папку с именем [customName] или именем папки. Возвращает
  /// false, если папка уже в закладках.
  Future<bool> addFromFolder(String folderPath, {String? customName}) async {
    if (byPath(folderPath) != null) return false;
    final order = _bookmarks.isEmpty ? 0 : _bookmarks.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1;
    final name = customName?.trim().isNotEmpty ?? false ? customName!.trim() : p.basename(folderPath);
    await _set([
      ..._bookmarks,
      Bookmark.create(
        name: name,
        path: p.normalize(folderPath),
        createdAt: _clock().millisecondsSinceEpoch,
        order: order,
      ),
    ]);
    return true;
  }

  Future<void> remove(String id) => _set([..._bookmarks.where((b) => b.id != id)]);

  Future<void> rename(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(newName, 'newName', 'must not be empty');
    await _set([for (final b in _bookmarks) b.id == id ? b.copyWith(name: trimmed) : b]);
  }

  /// Папка переехала: закладки на неё и на папки внутри неё получают новый
  /// путь, имена не меняются.
  Future<void> updatePath(String oldPath, String newPath) async {
    var changed = false;
    final updated = [
      for (final b in _bookmarks)
        if (p.equals(b.path, oldPath) || p.isWithin(oldPath, b.path))
          () {
            changed = true;
            return b.copyWith(path: p.normalize(p.join(newPath, p.relative(b.path, from: oldPath))));
          }()
        else
          b,
    ];
    if (changed) await _set(updated);
  }

  /// Удаляет закладки на папку [prefix] и на всё внутри неё.
  /// Decision: сравнение по частям пути, а не по строке — «/a/Поход» не
  /// задевает «/a/Поход 2».
  Future<void> removeByPathPrefix(String prefix) async {
    final kept = [
      for (final b in _bookmarks)
        if (!(p.equals(b.path, prefix) || p.isWithin(prefix, b.path))) b,
    ];
    if (kept.length != _bookmarks.length) await _set(kept);
  }

  /// Есть ли закладки на папку [path] или на что-то внутри неё.
  bool hasUnder(String path) => _bookmarks.any((b) => p.equals(b.path, path) || p.isWithin(path, b.path));

  Future<void> clear() => _set(const []);

  Future<void> _set(List<Bookmark> next) async {
    _bookmarks = List.unmodifiable(next);
    await _store.saveAll(_bookmarks);
    notifyListeners();
  }
}
