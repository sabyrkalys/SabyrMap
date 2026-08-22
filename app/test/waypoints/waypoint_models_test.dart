import 'package:app/waypoints/waypoint_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Waypoint.fromJson', () {
    test('parses geom coordinates as [lng, lat] into lat/lng fields', () {
      final json = {
        'id': 'w1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Trailhead',
        'type': 'camp',
        'note': 'Bring water',
        'geom': {
          'type': 'Point',
          'coordinates': [7.6, 45.9],
        },
        'can_edit': true,
        'created_at': '2026-08-22T10:00:00Z',
      };

      final waypoint = Waypoint.fromJson(json);

      expect(waypoint.id, 'w1');
      expect(waypoint.orgId, 'o1');
      expect(waypoint.ownerId, 'u1');
      expect(waypoint.name, 'Trailhead');
      expect(waypoint.type, 'camp');
      expect(waypoint.note, 'Bring water');
      expect(waypoint.lng, 7.6);
      expect(waypoint.lat, 45.9);
      expect(waypoint.canEdit, true);
      expect(waypoint.createdAt, DateTime.parse('2026-08-22T10:00:00Z'));
    });

    test('note is null when absent from JSON', () {
      final json = {
        'id': 'w1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Trailhead',
        'type': 'generic',
        'note': null,
        'geom': {
          'type': 'Point',
          'coordinates': [1.0, 2.0],
        },
        'can_edit': false,
        'created_at': '2026-08-22T10:00:00Z',
      };

      final waypoint = Waypoint.fromJson(json);

      expect(waypoint.note, isNull);
    });
  });

  test('WaypointException.toString includes the message', () {
    const exception = WaypointException('Could not create waypoint');
    expect(exception.toString(), 'WaypointException: Could not create waypoint');
  });
}
