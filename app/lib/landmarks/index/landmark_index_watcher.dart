import 'dart:async';

import 'package:app/storage/storage_service.dart';
import 'package:watcher/watcher.dart';

import 'landmark_index.dart';

/// Правки папки меток извне (Syncthing, файловый менеджер) — в индекс.
/// Свои записи индекс получает от репозитория сразу; повторное чтение
/// после события наблюдателя ничего не меняет.
///
/// Decision: события копятся [debounce] и уходят одним [LandmarkIndex.refresh]
/// — атомарная запись (временный файл + переименование) и копирование
/// папки дают пачку событий. Временные файлы атомарной записи
/// ([StorageService.tempMarker]) пропускаются.
class LandmarkIndexWatcher {
  LandmarkIndexWatcher(this._index, {this.debounce = const Duration(milliseconds: 500), Watcher? watcher})
    : _watcher = watcher ?? DirectoryWatcher(_index.root);

  final LandmarkIndex _index;
  final Watcher _watcher;
  final Duration debounce;

  final Set<String> _pending = {};
  StreamSubscription<WatchEvent>? _subscription;
  Timer? _timer;

  /// Начинает следить; ошибки наблюдателя (папку удалили, платформа не
  /// умеет) не роняют приложение — индекс остаётся на записях репозитория.
  void start() {
    _subscription ??= _watcher.events.listen(_onEvent, onError: (Object _) {});
  }

  /// Готов к событиям (для тестов: события до готовности теряются).
  Future<void> get ready => _watcher.ready;

  void _onEvent(WatchEvent event) {
    if (event.path.contains(StorageService.tempMarker)) return;
    _pending.add(event.path);
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final paths = _pending.toList();
    _pending.clear();
    await _index.refresh(paths);
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
  }
}
