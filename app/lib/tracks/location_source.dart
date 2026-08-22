import 'package:geolocator/geolocator.dart';

import 'track_models.dart';

abstract class LocationSource {
  /// Requests location permission if not already granted, and confirms the
  /// device's location service is enabled. Returns false if recording
  /// cannot proceed for any reason (permission denied, denied forever, or
  /// location services disabled).
  Future<bool> ensurePermission();

  /// A stream of positions, filtered so a new event only fires once the
  /// device has moved at least [distanceFilterMeters] from the last
  /// reported position.
  Stream<TrackPoint> positionStream({required int distanceFilterMeters});
}

class GeolocatorLocationSource implements LocationSource {
  @override
  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Stream<TrackPoint> positionStream({required int distanceFilterMeters}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(distanceFilter: distanceFilterMeters),
    ).map((position) => TrackPoint(lat: position.latitude, lng: position.longitude));
  }
}
