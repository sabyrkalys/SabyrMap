import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter/foundation.dart';

/// «Метки на экране»: каждая метка (файл) сразу на экране — и новая, и
/// загруженная. Хранятся только исключения, по путям:
/// - скрытые глазом — в списке «Метки на экране», но не на карте;
/// - убранные — ни в списке, ни на карте, пока их снова не покажут
///   («Показать» в «Все метки»).
class OnScreenRegistry extends ChangeNotifier {
  OnScreenRegistry([this._settings]);

  final AppSettings? _settings;

  Set<String> _hidden = const {};
  Set<String> _removed = const {};

  bool isOnScreen(String path) => !_removed.contains(path);

  /// На экране и не скрыта глазом — видна на карте.
  bool isVisible(String path) => isOnScreen(path) && !_hidden.contains(path);

  void hide(String path) => hideAll([path]);

  void hideAll(Iterable<String> paths) => _set(hidden: {..._hidden, ...paths});

  /// Возвращает на экран и делает видимой.
  void show(String path) => showAll([path]);

  void showAll(Iterable<String> paths) {
    final shown = paths.toSet();
    _set(hidden: _hidden.difference(shown), removed: _removed.difference(shown));
  }

  /// Видимую скрывает, остальную показывает; возвращает, видна ли теперь.
  bool toggle(String path) {
    final shown = !isVisible(path);
    shown ? show(path) : hide(path);
    return shown;
  }

  /// Убирает с экрана: файлы не трогаются.
  void removeAll(Iterable<String> paths) {
    final removed = paths.toSet();
    _set(hidden: _hidden.difference(removed), removed: {..._removed, ...removed});
  }

  /// Файл переименован или перенесён: его состояние переходит на [to].
  void moved(String from, String to) {
    if (!_hidden.contains(from) && !_removed.contains(from)) return;
    Set<String> move(Set<String> s) => s.contains(from)
        ? ({...s}
            ..remove(from)
            ..add(to))
        : s;
    _set(hidden: move(_hidden), removed: move(_removed));
  }

  /// Читает состояние из настроек; нет записи или она повреждена — всё на
  /// экране.
  void restore() {
    final raw = _settings?.getString(SettingsKeys.onScreenLandmarks);
    var hidden = <String>{};
    var removed = <String>{};
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        hidden = {for (final p in json['hidden'] as List<dynamic>? ?? const []) p as String};
        removed = {for (final p in json['removed'] as List<dynamic>? ?? const []) p as String};
      } on Object {
        hidden = {};
        removed = {};
      }
    }
    _hidden = Set.unmodifiable(hidden);
    _removed = Set.unmodifiable(removed);
    notifyListeners();
  }

  void _set({Set<String>? hidden, Set<String>? removed}) {
    final h = hidden ?? _hidden;
    final r = removed ?? _removed;
    if (setEquals(h, _hidden) && setEquals(r, _removed)) return;
    _hidden = Set.unmodifiable(h);
    _removed = Set.unmodifiable(r);
    notifyListeners();
    _settings?.setString(
      SettingsKeys.onScreenLandmarks,
      jsonEncode({'hidden': _hidden.toList()..sort(), 'removed': _removed.toList()..sort()}),
    );
  }
}
