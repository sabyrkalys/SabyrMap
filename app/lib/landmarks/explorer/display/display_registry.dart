import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter/foundation.dart';

import 'display_state.dart';

/// Какие файлы меток показаны на карте. Хранит только пути.
class DisplayRegistry extends ChangeNotifier {
  DisplayState _state = const DisplayState();

  DisplayState get state => _state;

  void display(String path) => _set(_state.withDisplayed(path));

  void displayAll(Iterable<String> paths) => _set(DisplayState(displayedPaths: Set.unmodifiable({..._state.displayedPaths, ...paths})));

  void undisplay(String path) => _set(_state.withUndisplayed(path));

  void undisplayAll(Iterable<String> paths) {
    final remove = paths.toSet();
    _set(DisplayState(displayedPaths: Set.unmodifiable(_state.displayedPaths.where((p) => !remove.contains(p)).toSet())));
  }

  /// Показывает скрытый файл и скрывает показанный; возвращает, показан
  /// ли он теперь.
  bool toggle(String path) {
    final shown = !isDisplayed(path);
    shown ? display(path) : undisplay(path);
    return shown;
  }

  void clear() => _set(const DisplayState());

  bool isDisplayed(String path) => _state.isDisplayed(path);
  int get count => _state.count;

  /// Оставляет только пути из [existingPaths] — все пути, которые точно
  /// существуют; остальные (удалённые файлы) убираются.
  void prune(Iterable<String> existingPaths) {
    final existing = existingPaths.toSet();
    _set(DisplayState(displayedPaths: Set.unmodifiable(_state.displayedPaths.where(existing.contains).toSet())));
  }

  /// Сохраняет показанные пути рабочего пространства [workspaceId] —
  /// JSON-список.
  Future<void> persist(String workspaceId, AppSettings settings) =>
      settings.setString(_key(workspaceId), jsonEncode(_state.displayedPaths.toList()..sort()));

  /// Восстанавливает пути рабочего пространства. Нет записи или она
  /// повреждена — на карте ничего.
  Future<void> restore(String workspaceId, AppSettings settings) async {
    final raw = settings.getString(_key(workspaceId));
    var paths = <String>{};
    if (raw != null) {
      try {
        paths = {for (final p in jsonDecode(raw) as List<dynamic>) p as String};
      } on Object {
        paths = {};
      }
    }
    _set(DisplayState(displayedPaths: Set.unmodifiable(paths)));
  }

  static String _key(String workspaceId) => '${SettingsKeys.displayedPrefix}$workspaceId';

  void _set(DisplayState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
