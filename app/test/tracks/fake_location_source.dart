import 'dart:async';

import 'package:app/tracks/location_source.dart';
import 'package:app/tracks/track_models.dart';

class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.permissionGranted = true, this.currentPosition});

  bool permissionGranted;

  /// Test-controlled result for [getCurrentPosition] when permission is
  /// granted. Leave null to simulate a position that never resolves (e.g.
  /// GPS unavailable even though permission was granted).
  TrackPoint? currentPosition;

  final _controller = StreamController<TrackPoint>.broadcast();
  int? lastDistanceFilterMeters;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Stream<TrackPoint> positionStream({required int distanceFilterMeters}) {
    lastDistanceFilterMeters = distanceFilterMeters;
    return _controller.stream;
  }

  @override
  Future<TrackPoint?> getCurrentPosition() async {
    if (!permissionGranted) return null;
    return currentPosition;
  }

  /// Test-only: simulates the device reporting a new position.
  void emit(TrackPoint point) => _controller.add(point);

  void dispose() => _controller.close();
}
