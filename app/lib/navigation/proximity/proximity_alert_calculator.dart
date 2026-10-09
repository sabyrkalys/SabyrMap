import 'proximity_alert_signal.dart';
import 'proximity_zone.dart';

export 'proximity_alert_signal.dart' show ProximitySignalKind;

/// Зоны и сигналы оповещений о приближении.
abstract final class ProximityAlertCalculator {
  /// Зона по расстоянию до центра.
  static ProximityZone zone({required double distanceMeters, required double radiusMeters}) {
    if (distanceMeters <= radiusMeters / 4) return ProximityZone.inner;
    if (distanceMeters <= radiusMeters / 2) return ProximityZone.middle;
    if (distanceMeters <= radiusMeters) return ProximityZone.outer;
    return ProximityZone.outside;
  }

  /// Сигнал при переходе [from] → [to]. Выход из радиуса (outer → outside)
  /// сигналит, только если до этого были внутри ([wasInside]); прочие
  /// переходы, в том числе скачки через зону, — тишина.
  static ProximitySignalKind signalFor({
    required ProximityZone from,
    required ProximityZone to,
    required bool wasInside,
  }) => switch ((from, to)) {
    (ProximityZone.outside, ProximityZone.outer) => ProximitySignalKind.goodWay1,
    (ProximityZone.outer, ProximityZone.middle) => ProximitySignalKind.goodWay2,
    (ProximityZone.middle, ProximityZone.inner) => ProximitySignalKind.goodWay3,
    (ProximityZone.inner, ProximityZone.middle) => ProximitySignalKind.wrongWay1,
    (ProximityZone.middle, ProximityZone.outer) => ProximitySignalKind.wrongWay1,
    (ProximityZone.outer, ProximityZone.outside) when wasInside => ProximitySignalKind.wrongWay2,
    _ => ProximitySignalKind.silence,
  };
}
