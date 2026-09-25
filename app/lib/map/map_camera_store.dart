import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// The view the map opens with before a saved or GPS position is applied.
const initialMapCamera = CameraPosition(target: LatLng(0, 0), zoom: 1);

/// Pure decision for when a settled camera should be saved: the untouched
/// startup view is skipped, otherwise a first launch without GPS would save
/// the world view and every later launch would restore it instead of
/// centering on the device's location.
bool shouldPersistCamera(CameraPosition position, {required bool cameraRestored}) {
  if (cameraRestored) return true;
  return position.target != initialMapCamera.target || position.zoom != initialMapCamera.zoom;
}

abstract class MapCameraStore {
  Future<CameraPosition?> load();
  Future<void> save(CameraPosition position);
}

/// Remembers the last map view on the device so the map reopens where the
/// user left it. Local-only, like the waypoint icon assignments.
class SecureMapCameraStore implements MapCameraStore {
  SecureMapCameraStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'map_camera';

  final FlutterSecureStorage _storage;

  @override
  Future<CameraPosition?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CameraPosition(
        target: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        zoom: (json['zoom'] as num).toDouble(),
        bearing: (json['bearing'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CameraPosition position) {
    return _storage.write(
      key: _key,
      value: jsonEncode({
        'lat': position.target.latitude,
        'lng': position.target.longitude,
        'zoom': position.zoom,
        'bearing': position.bearing,
      }),
    );
  }
}

final mapCameraStoreProvider = Provider<MapCameraStore>((ref) => SecureMapCameraStore());
