import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/tracks/track_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a GPS point becomes a file location with elevation, UTC time and accuracy in file units', () {
    final location = TrackPoint(
      lat: 48.5,
      lng: 37.1,
      elevationMeters: 212.345,
      time: DateTime.utc(2026, 10, 16, 8, 30),
      accuracyMeters: 4.25,
    ).toLocation();

    expect((location.latitude, location.longitude), (48.5, 37.1));
    expect(location.valueOf(LocationValueType.elevation)?.value, 212345);
    expect(location.valueOf(LocationValueType.utcTime)?.value, DateTime.utc(2026, 10, 16, 8, 30).millisecondsSinceEpoch);
    expect(location.valueOf(LocationValueType.accuracy)?.value, 425);
  });

  test('unknown time and accuracy are left out', () {
    final location = const TrackPoint(lat: 1, lng: 2).toLocation();
    expect(location.valueOf(LocationValueType.utcTime), isNull);
    expect(location.valueOf(LocationValueType.accuracy), isNull);
    expect(location.valueOf(LocationValueType.elevation)?.value, 0);
  });
}
