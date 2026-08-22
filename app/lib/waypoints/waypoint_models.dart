class Waypoint {
  const Waypoint({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.note,
    required this.lat,
    required this.lng,
    required this.canEdit,
    required this.createdAt,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String name;
  final String type;
  final String? note;
  final double lat;
  final double lng;
  final bool canEdit;
  final DateTime createdAt;

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    final geom = json['geom'] as Map<String, dynamic>;
    final coordinates = geom['coordinates'] as List<dynamic>;
    return Waypoint(
      id: json['id'] as String,
      orgId: json['org_id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      note: json['note'] as String?,
      lng: (coordinates[0] as num).toDouble(),
      lat: (coordinates[1] as num).toDouble(),
      canEdit: json['can_edit'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WaypointException implements Exception {
  const WaypointException(this.message);

  final String message;

  @override
  String toString() => 'WaypointException: $message';
}
