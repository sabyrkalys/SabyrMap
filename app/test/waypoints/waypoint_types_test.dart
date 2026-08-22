import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every type has a color and the default type is in the list', () {
    expect(waypointTypes, contains(defaultWaypointType));
    for (final type in waypointTypes) {
      expect(waypointTypeColors.containsKey(type), isTrue, reason: 'missing color for $type');
    }
  });
}
