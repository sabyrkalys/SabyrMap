import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Просьба показать точку на карте («ЦЕНТРИРОВАТЬ» в детализации метки).
/// Карта слушает и переводит камеру; [MapFocusRequest.seq] отличает
/// повторную просьбу о той же точке.
class MapFocusRequest {
  const MapFocusRequest(this.point, this.seq);

  final LatLng point;
  final int seq;
}

class MapFocusController extends Notifier<MapFocusRequest?> {
  @override
  MapFocusRequest? build() => null;

  void focus(LatLng point) => state = MapFocusRequest(point, (state?.seq ?? 0) + 1);
}

final mapFocusProvider = NotifierProvider<MapFocusController, MapFocusRequest?>(MapFocusController.new);
