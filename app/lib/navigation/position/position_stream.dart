import 'dart:async';

import 'position_snapshot.dart';
import 'position_source.dart';

/// Общий поток положений для нескольких подписчиков: подписка на
/// источник одна (пока есть слушатели), положения — не чаще [minInterval].
class PositionStream {
  PositionStream(this._source, {this.minInterval = const Duration(seconds: 1), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _controller = StreamController<PositionSnapshot>.broadcast(onListen: _start, onCancel: _stop);
  }

  final PositionSource _source;

  /// Наименьший промежуток между событиями.
  final Duration minInterval;
  final DateTime Function() _clock;

  late final StreamController<PositionSnapshot> _controller;
  StreamSubscription<PositionSnapshot>? _subscription;
  DateTime? _lastEmitted;

  /// Положения; лишние (чаще [minInterval]) и неверные отбрасываются.
  Stream<PositionSnapshot> get stream => _controller.stream;

  void _start() {
    _subscription = _source
        .watch(interval: minInterval)
        .listen(_onPosition, onError: _controller.addError);
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastEmitted = null;
  }

  void _onPosition(PositionSnapshot snapshot) {
    if (!snapshot.isValid) return;
    final now = _clock();
    final last = _lastEmitted;
    if (last != null && now.difference(last) < minInterval) return;
    _lastEmitted = now;
    _controller.add(snapshot);
  }

  Future<void> close() async {
    await _stop();
    await _controller.close();
  }
}
