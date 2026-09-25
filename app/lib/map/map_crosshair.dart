import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Where the map's crosshair last settled; null until the map settles once.
/// Published by MapScreen so actions outside it (the МЕТКИ panel) can use it.
class MapCrosshair extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng position) => state = position;
}

final mapCrosshairProvider = NotifierProvider<MapCrosshair, LatLng?>(MapCrosshair.new);
