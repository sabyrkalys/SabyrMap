import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// What the map shows right now.
typedef MapViewport = ({LatLngBounds bounds, double zoom});

/// Lets screens outside the map (e.g. «Сохранить участок карты») ask for the
/// visible area. The map screen registers a reader once its controller
/// exists; before that [read] returns null.
class MapViewportNotifier extends Notifier<Future<MapViewport?> Function()?> {
  @override
  Future<MapViewport?> Function()? build() => null;

  void register(Future<MapViewport?> Function()? reader) => state = reader;

  Future<MapViewport?> read() async => state == null ? null : await state!();
}

final mapViewportProvider = NotifierProvider<MapViewportNotifier, Future<MapViewport?> Function()?>(MapViewportNotifier.new);
