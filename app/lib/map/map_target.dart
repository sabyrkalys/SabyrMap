import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// The «Задать цель» measuring tool: a point the crosshair measures to.
/// Memory only -- it is a tool, not an object, and is gone after a restart.
sealed class MapTargetState {
  const MapTargetState();

  LatLng? get point => null;
}

class MapTargetNone extends MapTargetState {
  const MapTargetNone();
}

/// Armed by «Задать цель»: the next map tap becomes the target.
class MapTargetPicking extends MapTargetState {
  const MapTargetPicking();
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

  void startPicking() => state = const MapTargetPicking();

  void pick(LatLng point) {
    if (state is MapTargetPicking) state = MapTargetSet(point);
  }

  void cancelPicking() {
    if (state is MapTargetPicking) state = const MapTargetNone();
  }

  void clear() => state = const MapTargetNone();
}

final mapTargetProvider = NotifierProvider<MapTargetController, MapTargetState>(MapTargetController.new);

/// Whether the crosshair context card is open. Opening it cancels a pending
/// target pick, so an armed «Задать цель» never swallows a later tap.
class CrosshairMenuOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void open() {
    ref.read(mapTargetProvider.notifier).cancelPicking();
    state = true;
  }

  void close() => state = false;

  void toggle() => state ? close() : open();
}

final crosshairMenuOpenProvider = NotifierProvider<CrosshairMenuOpen, bool>(CrosshairMenuOpen.new);

/// «350 м» under a kilometre, «1.2 км» from one kilometre up.
String formatDistance(double meters) {
  if (meters < 999.5) return '${meters.round()} м';
  return '${(meters / 1000).toStringAsFixed(1)} км';
}
