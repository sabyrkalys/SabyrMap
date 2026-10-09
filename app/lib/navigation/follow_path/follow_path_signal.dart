import 'dart:async';

import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:app/navigation/signals/signal_kind.dart';

import 'deviation_detector.dart';

/// Сигналы следования по треку.
enum FollowPathSignalKind { rightWay, wrongWay, singleRightWay, doubleRightWay, doubleWrongWay, tripleWrongWay }

/// Сигнал и как часто его повторять.
class FollowPathSignal {
  const FollowPathSignal(this.kind, {this.repeatEvery = defaultInterval});

  static const Duration defaultInterval = Duration(seconds: 5);

  final FollowPathSignalKind kind;
  final Duration repeatEvery;

  /// Сигнал для состояния; на треке — null (тишина).
  static FollowPathSignal? forState(DeviationState state) => switch (state) {
    DeviationState.onTrack => null,
    DeviationState.approaching => const FollowPathSignal(FollowPathSignalKind.rightWay),
    DeviationState.deviatingFar => const FollowPathSignal(FollowPathSignalKind.doubleWrongWay),
    DeviationState.deviatingVeryFar => const FollowPathSignal(FollowPathSignalKind.tripleWrongWay),
  };

  /// Звук для сигнала. Decision: «правильно» — goodWay1..3 по числу
  /// гудков, «неправильно» — wrongWay1, тройное — wrongWay2.
  static SignalKind soundOf(FollowPathSignalKind kind) => switch (kind) {
    FollowPathSignalKind.rightWay || FollowPathSignalKind.singleRightWay => SignalKind.goodWay1,
    FollowPathSignalKind.doubleRightWay => SignalKind.goodWay2,
    FollowPathSignalKind.wrongWay || FollowPathSignalKind.doubleWrongWay => SignalKind.wrongWay1,
    FollowPathSignalKind.tripleWrongWay => SignalKind.wrongWay2,
  };
}

/// Подаёт сигнал состояния отклонения: сразу при смене состояния и затем
/// каждые [interval], пока состояние не сменится. На треке — тишина.
class FollowPathSignalEmitter {
  FollowPathSignalEmitter(this._signaler, {this.interval = FollowPathSignal.defaultInterval, bool Function()? enabled})
    : _enabled = enabled ?? _always;

  final AudioSignaler _signaler;
  final Duration interval;
  final bool Function() _enabled;

  DeviationState? _state;
  Timer? _timer;

  static bool _always() => true;

  /// Текущее состояние, о котором сигналит эмиттер.
  DeviationState? get state => _state;

  /// Новое состояние отклонения.
  void update(DeviationState state) {
    if (state == _state) return;
    _state = state;
    _timer?.cancel();
    _timer = null;
    final signal = FollowPathSignal.forState(state);
    if (signal == null) return;
    _play(signal);
    _timer = Timer.periodic(interval, (_) => _play(signal));
  }

  /// Тишина и сброс состояния.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _state = null;
    await _signaler.stop();
  }

  void _play(FollowPathSignal signal) {
    if (_enabled()) unawaited(_signaler.play(FollowPathSignal.soundOf(signal.kind)));
  }
}
