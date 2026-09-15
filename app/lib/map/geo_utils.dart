import 'dart:math' as math;

const double _earthRadiusMeters = 6371000;

double _degToRad(double deg) => deg * math.pi / 180;
double _radToDeg(double rad) => rad * 180 / math.pi;

/// Great-circle distance between two points, in meters (haversine formula).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

/// Initial compass bearing (0-360, 0 = north) from point 1 to point 2.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _degToRad(lat1);
  final phi2 = _degToRad(lat2);
  final dLng = _degToRad(lng2 - lng1);
  final y = math.sin(dLng) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
  final theta = math.atan2(y, x);
  return (_radToDeg(theta) + 360) % 360;
}
