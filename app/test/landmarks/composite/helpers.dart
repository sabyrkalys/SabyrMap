import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_waypoint.dart';

/// Точка; [ele] — высота в метрах, [t] — время Unix ms.
LandmarkLocation loc(double lat, double lon, {double? ele, int? t}) => LandmarkLocation(
  latitude: lat,
  longitude: lon,
  values: [
    if (ele != null) LocationValue(type: LocationValueType.elevation, value: (ele * 1000).round()),
    if (t != null) LocationValue(type: LocationValueType.utcTime, value: t),
  ],
);

WaypointObject wp(double lat, double lon, [String? name]) => WaypointObject(
  location: LandmarkLocation(latitude: lat, longitude: lon),
  userMetadata: name == null ? const LandmarkMetadata() : LandmarkMetadata(entries: {'name': name}),
);
