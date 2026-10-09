import 'package:app/storage/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'offline_area_estimator.dart';
import 'offline_area_progress.dart';
import 'offline_area_request.dart';

/// Состояние сохранения области.
enum OfflineAreaStatus { idle, running, paused, completed }

/// Сохранение области офлайн: оценка, статус и ход. Саму загрузку ведёт
/// внешний слой и сообщает ход через [updateProgress].
class OfflineAreaController extends ChangeNotifier {
  OfflineAreaController(this._estimator, this._storage);

  final OfflineAreaEstimator _estimator;
  final StorageService _storage;

  OfflineAreaRequest? _request;
  OfflineAreaProgress? _progress;
  OfflineAreaStatus _status = OfflineAreaStatus.idle;

  OfflineAreaRequest? get request => _request;
  OfflineAreaProgress? get progress => _progress;
  OfflineAreaStatus get status => _status;
  bool get isRunning => _status == OfflineAreaStatus.running;

  /// Кэш тайлов источника: `<корень>/datastore/maps/cache/<sourceId>`.
  String cacheFolder(String sourceId) => p.join(_storage.paths.datastoreMaps, 'cache', sourceId);

  /// Пересчитывает оценку запроса.
  Future<OfflineAreaRequest> estimate(OfflineAreaRequest req) async => _estimator.estimateRequest(req);

  /// Начинает сохранение (с оценкой). Уже идущее — [StateError].
  Future<void> start(OfflineAreaRequest req) async {
    if (isRunning) throw StateError('An offline area is already being saved');
    final estimated = await estimate(req);
    _request = estimated;
    _progress = OfflineAreaProgress(downloadedTiles: 0, totalTiles: estimated.estimatedTileCount);
    _status = estimated.estimatedTileCount == 0 ? OfflineAreaStatus.completed : OfflineAreaStatus.running;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_status != OfflineAreaStatus.running) return;
    _status = OfflineAreaStatus.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_status != OfflineAreaStatus.paused) return;
    _status = OfflineAreaStatus.running;
    notifyListeners();
  }

  /// Прекращает; уже скачанное остаётся в кэше.
  Future<void> cancel() async {
    _request = null;
    _progress = null;
    _status = OfflineAreaStatus.idle;
    notifyListeners();
  }

  /// Ход от загрузчика; при полном счёте — завершено. Вне работы — ничего.
  void updateProgress({required int downloadedTiles, int bytesDownloaded = 0}) {
    final current = _progress;
    if (current == null || _status != OfflineAreaStatus.running) return;
    _progress = OfflineAreaProgress(
      downloadedTiles: downloadedTiles.clamp(0, current.totalTiles),
      totalTiles: current.totalTiles,
      bytesDownloaded: bytesDownloaded,
    );
    if (_progress!.isComplete) _status = OfflineAreaStatus.completed;
    notifyListeners();
  }

  /// Удаляет кэш тайлов источника.
  Future<void> clearData(String sourceId) async {
    if (sourceId.isEmpty || sourceId.contains('/') || sourceId.contains('..')) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must be a plain id');
    }
    await _storage.deleteDirectory(cacheFolder(sourceId));
  }
}
