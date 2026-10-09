import 'package:app/landmarks/composite/operations/waypoint_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final a = wp(0, 0, 'a');
  final b = wp(1, 1, 'b');
  final c = wp(2, 2, 'c');
  List<String?> names(List list) => [for (final w in list) w.userMetadata.name as String?];

  test('add at the end, at 0, in the middle, into an empty list', () {
    expect(names(WaypointOps.add([a, b], c)), ['a', 'b', 'c']);
    expect(names(WaypointOps.add([a, b], c, atIndex: 0)), ['c', 'a', 'b']);
    expect(names(WaypointOps.add([a, b], c, atIndex: 1)), ['a', 'c', 'b']);
    expect(names(WaypointOps.add([], a)), ['a']);
    expect(() => WaypointOps.add([a], b, atIndex: 2), throwsRangeError);
  });

  test('removeAt first and last; out of range', () {
    expect(names(WaypointOps.removeAt([a, b, c], 0)), ['b', 'c']);
    expect(names(WaypointOps.removeAt([a, b, c], 2)), ['a', 'b']);
    expect(() => WaypointOps.removeAt([], 0), throwsRangeError);
  });

  test('replaceAt', () {
    expect(names(WaypointOps.replaceAt([a, b], 1, c)), ['a', 'c']);
    expect(() => WaypointOps.replaceAt([a], 1, c), throwsRangeError);
  });

  test('reorder moves an element to the target place', () {
    expect(names(WaypointOps.reorder([a, b, c], 0, 2)), ['b', 'c', 'a']);
    expect(names(WaypointOps.reorder([a, b, c], 2, 0)), ['c', 'a', 'b']);
    expect(names(WaypointOps.reorder([a, b, c], 1, 1)), ['a', 'b', 'c']);
    expect(() => WaypointOps.reorder([a], 0, 1), throwsRangeError);
  });

  test('reverseOrder; the input is not changed', () {
    final list = [a, b, c];
    expect(names(WaypointOps.reverseOrder(list)), ['c', 'b', 'a']);
    expect(WaypointOps.reverseOrder([]), isEmpty);
    WaypointOps.removeAt(list, 0);
    expect(list, hasLength(3));
  });
}
