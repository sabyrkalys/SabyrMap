class TrackPoint {
  const TrackPoint({required this.lat, required this.lng, this.elevationMeters = 0.0});

  final double lat;
  final double lng;
  final double elevationMeters;
}

class Track {
  const Track({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.points,
    required this.createdAt,
    this.lengthMeters = 0.0,
    this.durationSeconds,
    this.elevationGainMeters,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String name;
  final List<TrackPoint> points;
  final DateTime createdAt;
  final double lengthMeters;
  final int? durationSeconds;
  final double? elevationGainMeters;

  factory Track.fromJson(Map<String, dynamic> json) {
    final geom = json['geom'] as Map<String, dynamic>;
    final coordinates = geom['coordinates'] as List<dynamic>;
    return Track(
      id: json['id'] as String,
      orgId: json['org_id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      points: [
        for (final c in coordinates)
          TrackPoint(
            lng: ((c as List<dynamic>)[0] as num).toDouble(),
            lat: (c[1] as num).toDouble(),
            elevationMeters: c.length > 2 ? (c[2] as num).toDouble() : 0.0,
          ),
      ],
      createdAt: DateTime.parse(json['created_at'] as String),
      lengthMeters: (json['length_meters'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      elevationGainMeters: (json['elevation_gain_meters'] as num?)?.toDouble(),
    );
  }
}

class TrackException implements Exception {
  const TrackException(this.message);

  final String message;

  @override
  String toString() => 'TrackException: $message';
}
