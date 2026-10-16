import 'package:app/landmarks/models/landmark_location.dart';

/// Точка записи трека от GPS.
class TrackPoint {
  const TrackPoint({required this.lat, required this.lng, this.elevationMeters = 0.0, this.time, this.accuracyMeters});

  final double lat;
  final double lng;
  final double elevationMeters;

  /// Когда снята; null — неизвестно.
  final DateTime? time;

  /// Горизонтальная точность, м; null — неизвестна.
  final double? accuracyMeters;

  /// Точка трека в файле меток: высота, время и точность — в масштабе
  /// формата ([LocationValueType]).
  LandmarkLocation toLocation() => LandmarkLocation(
    latitude: lat,
    longitude: lng,
    values: [
      LocationValue(type: LocationValueType.elevation, value: (elevationMeters * 1000).round()),
      if (time case final t?) LocationValue(type: LocationValueType.utcTime, value: t.toUtc().millisecondsSinceEpoch),
      if (accuracyMeters case final a? when a.isFinite && a >= 0)
        LocationValue(type: LocationValueType.accuracy, value: (a * 100).round()),
    ],
  );
}
