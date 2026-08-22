import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Track.fromJson', () {
    test('parses geom coordinates as [lng, lat] pairs into TrackPoint(lat, lng)', () {
      final json = {
        'id': 't1',
        'org_id': 'o1',
        'owner_id': 'u1',
        'name': 'Morning walk',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9],
            [7.7, 46.0],
          ],
        },
        'created_at': '2026-08-22T10:00:00Z',
      };

      final track = Track.fromJson(json);

      expect(track.id, 't1');
      expect(track.orgId, 'o1');
      expect(track.ownerId, 'u1');
      expect(track.name, 'Morning walk');
      expect(track.points, hasLength(2));
      expect(track.points[0].lng, 7.6);
      expect(track.points[0].lat, 45.9);
      expect(track.points[1].lng, 7.7);
      expect(track.points[1].lat, 46.0);
      expect(track.createdAt, DateTime.parse('2026-08-22T10:00:00Z'));
    });
  });

  test('TrackException.toString includes the message', () {
    const exception = TrackException('Could not create track');
    expect(exception.toString(), 'TrackException: Could not create track');
  });
}
