import 'package:app/navigation/follow_path/deviation_detector.dart';
import 'package:app/navigation/follow_path/follow_path_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const d = DeviationDetector();
  DeviationState eval(double current, double previous, {bool signaled = false}) =>
      d.evaluate(currentDistance: current, previousDistance: previous, threshold: 50, wasSignaled: signaled);

  test('on track within the threshold', () {
    expect(eval(50, 10), DeviationState.onTrack);
    expect(eval(0, 0), DeviationState.onTrack);
  });

  test('approaching when the distance shrinks off track', () {
    expect(eval(70, 80), DeviationState.approaching);
    expect(eval(100, 120), DeviationState.approaching);
  });

  test('deviating far when beyond the threshold and moving away', () {
    expect(eval(60, 55), DeviationState.deviatingFar);
    expect(eval(75, 75), DeviationState.deviatingFar);
  });

  test('deviating very far beyond 1.5 × threshold', () {
    expect(eval(76, 70), DeviationState.deviatingVeryFar);
  });

  test('after a signal, back on track only below 80 % of the threshold', () {
    expect(eval(45, 46, signaled: true), DeviationState.approaching);
    expect(eval(40, 45, signaled: true), DeviationState.onTrack);
  });

  test('state to signal mapping', () {
    expect(FollowPathSignal.forState(DeviationState.onTrack), isNull);
    expect(FollowPathSignal.forState(DeviationState.approaching)!.kind, FollowPathSignalKind.rightWay);
    expect(FollowPathSignal.forState(DeviationState.deviatingFar)!.kind, FollowPathSignalKind.doubleWrongWay);
    expect(FollowPathSignal.forState(DeviationState.deviatingVeryFar)!.kind, FollowPathSignalKind.tripleWrongWay);
  });
}
