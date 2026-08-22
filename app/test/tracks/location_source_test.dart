import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TrackPoint carries lat/lng as doubles', () {
    const point = TrackPoint(lat: 45.9, lng: 7.6);
    expect(point.lat, 45.9);
    expect(point.lng, 7.6);
  });
}
