import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location_source.dart';

void main() {
  test('TrackPoint carries lat/lng as doubles', () {
    const point = TrackPoint(lat: 45.9, lng: 7.6);
    expect(point.lat, 45.9);
    expect(point.lng, 7.6);
  });

  group('getCurrentPosition', () {
    test('returns null when permission is not granted', () async {
      final source = FakeLocationSource(permissionGranted: false, currentPosition: const TrackPoint(lat: 1, lng: 2));

      expect(await source.getCurrentPosition(), isNull);
    });

    test('returns the current position when permission is granted', () async {
      final source = FakeLocationSource(currentPosition: const TrackPoint(lat: 45.9, lng: 7.6));

      final result = await source.getCurrentPosition();

      expect(result?.lat, 45.9);
      expect(result?.lng, 7.6);
    });

    test('returns null when permission is granted but no position is available', () async {
      final source = FakeLocationSource();

      expect(await source.getCurrentPosition(), isNull);
    });
  });
}
