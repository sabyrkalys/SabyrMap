import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// The «Задать цель» measuring tool: a start point the crosshair measures from.
/// Memory only -- it is a tool, not an object, and is gone after a restart.
sealed class MapTargetState {
  const MapTargetState();

  LatLng? get point => null;
}

class MapTargetNone extends MapTargetState {
  const MapTargetNone();
}

class MapTargetSet extends MapTargetState {
  const MapTargetSet(this._point);

  final LatLng _point;

  @override
  LatLng get point => _point;
}

class MapTargetController extends Notifier<MapTargetState> {
  @override
  MapTargetState build() => const MapTargetNone();

  /// «Задать цель»: [point] (the spot under the crosshair) becomes the
  /// start of the measurement; the crosshair is its other end.
  void setAt(LatLng point) => state = MapTargetSet(point);

  void clear() => state = const MapTargetNone();
}

final mapTargetProvider = NotifierProvider<MapTargetController, MapTargetState>(MapTargetController.new);

/// Whether the crosshair context card is open.
class CrosshairMenuOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void close() => state = false;

  void toggle() => state ? close() : open();
}

final crosshairMenuOpenProvider = NotifierProvider<CrosshairMenuOpen, bool>(CrosshairMenuOpen.new);

/// «349.6 м» (to 0.1 m) under a kilometre, «1.2 км» from one kilometre up.
String formatDistance(double meters) {
  if (meters < 999.95) return '${meters.toStringAsFixed(1)} м';
  return '${(meters / 1000).toStringAsFixed(1)} км';
}
