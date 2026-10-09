import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:path/path.dart' as p;

import 'bookmark.dart';

/// Закладки в настройках: JSON-массив под `explorer.bookmarks`.
class BookmarkStore {
  BookmarkStore(this._settings);

  final AppSettings _settings;

  /// Закладки по порядку. Decision: первая версия хранила просто пути —
  /// такие записи читаются как закладки с именем папки, поэтому старые
  /// закладки не теряются. Повреждённая запись — пусто.
  Future<List<Bookmark>> loadAll() async {
    final raw = _settings.getString(SettingsKeys.explorerBookmarks);
    if (raw == null) return const [];
    try {
      final out = <Bookmark>[];
      for (final (i, e) in (jsonDecode(raw) as List<dynamic>).indexed) {
        out.add(switch (e) {
          final String path => Bookmark(id: path, name: p.basename(path), path: path, createdAt: 0, order: i),
          final Map<String, dynamic> json => Bookmark.fromJson(json),
          _ => throw const FormatException('bad bookmark'),
        });
      }
      return out..sort((a, b) => a.order.compareTo(b.order));
    } on Object {
      return const [];
    }
  }

  Future<void> saveAll(List<Bookmark> bookmarks) =>
      _settings.setString(SettingsKeys.explorerBookmarks, jsonEncode([for (final b in bookmarks) b.toJson()]));
}
