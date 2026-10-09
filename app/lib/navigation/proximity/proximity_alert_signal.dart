import 'dart:async';

import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:app/navigation/signals/signal_kind.dart';

/// Сигнал оповещения о приближении.
enum ProximitySignalKind {
  silence,
  goodWay1,
  goodWay2,
  goodWay3,
  wrongWay1,
  wrongWay2;

  /// Звук; у тишины — null.
  SignalKind? get sound => switch (this) {
    silence => null,
    goodWay1 => SignalKind.goodWay1,
    goodWay2 => SignalKind.goodWay2,
    goodWay3 => SignalKind.goodWay3,
    wrongWay1 => SignalKind.wrongWay1,
    wrongWay2 => SignalKind.wrongWay2,
  };
}

/// Подаёт сигналы оповещений: при переходе — сразу; если у оповещения
/// включён повтор — каждые [interval], пока не придёт следующий переход.
/// Выход из радиуса (wrongWay2) звучит один раз, затем тишина.
class ProximityAlertSignalEmitter {
  ProximityAlertSignalEmitter(this._signaler, {this.interval = defaultInterval, bool Function()? enabled})
    : _enabled = enabled ?? _always;

  static const Duration defaultInterval = Duration(seconds: 3);

  final AudioSignaler _signaler;
  final Duration interval;
  final bool Function() _enabled;
  final Map<String, Timer> _timers = {};

  static bool _always() => true;

  /// Переход оповещения [alertId] с сигналом [kind].
  void onTransition(String alertId, ProximitySignalKind kind, {required bool repeat}) {
    cancel(alertId);
    final sound = kind.sound;
    if (sound == null) return;
    _play(sound);
    if (repeat && kind != ProximitySignalKind.wrongWay2) {
      _timers[alertId] = Timer.periodic(interval, (_) => _play(sound));
    }
  }

  /// Прекратить повтор для [alertId].
  void cancel(String alertId) => _timers.remove(alertId)?.cancel();

  /// Тишина по всем оповещениям.
  Future<void> stopAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _signaler.stop();
  }

  void _play(SignalKind sound) {
    if (_enabled()) unawaited(_signaler.play(sound));
  }
}
