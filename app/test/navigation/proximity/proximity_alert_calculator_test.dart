import 'package:app/navigation/proximity/proximity_alert_calculator.dart';
import 'package:app/navigation/proximity/proximity_zone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProximityZone zone(double d) => ProximityAlertCalculator.zone(distanceMeters: d, radiusMeters: 100);

  test('zones by distance', () {
    expect(zone(0), ProximityZone.inner);
    expect(zone(25), ProximityZone.inner);
    expect(zone(26), ProximityZone.middle);
    expect(zone(50), ProximityZone.middle);
    expect(zone(51), ProximityZone.outer);
    expect(zone(100), ProximityZone.outer);
    expect(zone(100.1), ProximityZone.outside);
  });

  ProximitySignalKind signal(ProximityZone from, ProximityZone to, {bool wasInside = true}) =>
      ProximityAlertCalculator.signalFor(from: from, to: to, wasInside: wasInside);

  test('every mapped transition', () {
    expect(signal(ProximityZone.outside, ProximityZone.outer, wasInside: false), ProximitySignalKind.goodWay1);
    expect(signal(ProximityZone.outer, ProximityZone.middle), ProximitySignalKind.goodWay2);
    expect(signal(ProximityZone.middle, ProximityZone.inner), ProximitySignalKind.goodWay3);
    expect(signal(ProximityZone.inner, ProximityZone.middle), ProximitySignalKind.wrongWay1);
    expect(signal(ProximityZone.middle, ProximityZone.outer), ProximitySignalKind.wrongWay1);
    expect(signal(ProximityZone.outer, ProximityZone.outside), ProximitySignalKind.wrongWay2);
  });

  test('other transitions are silent', () {
    expect(signal(ProximityZone.outside, ProximityZone.inner), ProximitySignalKind.silence);
    expect(signal(ProximityZone.inner, ProximityZone.outside), ProximitySignalKind.silence);
    expect(signal(ProximityZone.middle, ProximityZone.middle), ProximitySignalKind.silence);
    expect(signal(ProximityZone.outer, ProximityZone.outside, wasInside: false), ProximitySignalKind.silence);
  });
}
