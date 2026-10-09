import 'package:app/navigation/measure/measure_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late MeasureController c;
  setUp(() => c = MeasureController());

  test('addPoint adds, recomputes and opens the panel', () {
    expect(c.state.isActive, isFalse);
    c.addPoint(loc(0, 0));
    c.addPoint(loc(0, 1));
    c.addPoint(loc(1, 1));
    expect(c.state.points, hasLength(3));
    expect(c.state.segments, hasLength(2));
    expect(c.state.totalDistanceMeters, greaterThan(200000));
    expect(c.state.isActive, isTrue);
  });

  test('removeLast drops the last point', () {
    c.addPoint(loc(0, 0));
    c.addPoint(loc(0, 1));
    c.removeLast();
    expect(c.state.points, [loc(0, 0)]);
    expect(c.state.segments, isEmpty);
    expect(c.state.totalDistanceMeters, 0);
    c.removeLast();
    c.removeLast();
    expect(c.state.points, isEmpty);
  });

  test('clear empties everything', () {
    c.addPoint(loc(0, 0));
    c.addPoint(loc(0, 1));
    c.clear();
    expect(c.state.points, isEmpty);
    expect(c.state.segments, isEmpty);
    expect(c.state.isActive, isFalse);
    expect(c.state.hasMeasurement, isFalse);
  });

  test('close hides the panel and keeps the points; reopen shows it', () {
    c.addPoint(loc(0, 0));
    c.addPoint(loc(0, 1));
    c.close();
    expect(c.state.isActive, isFalse);
    expect(c.state.points, hasLength(2));
    expect(c.state.hasMeasurement, isTrue);
    c.reopen();
    expect(c.state.isActive, isTrue);
    expect(c.state.segments, hasLength(1));
  });

  test('listeners are notified', () {
    var notified = 0;
    c.addListener(() => notified++);
    c.addPoint(loc(0, 0));
    c.close();
    c.close();
    expect(notified, 2);
  });
}
