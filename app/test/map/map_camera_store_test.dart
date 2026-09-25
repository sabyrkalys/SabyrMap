import 'package:app/map/map_camera_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureMapCameraStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('load returns null when nothing was saved', () async {
      expect(await SecureMapCameraStore().load(), isNull);
    });

    test('save then load round-trips target, zoom and bearing', () async {
      final store = SecureMapCameraStore();
      await store.save(const CameraPosition(target: LatLng(47.99530, 37.81157), zoom: 14.5, bearing: 30));

      final loaded = await store.load();
      expect(loaded!.target.latitude, closeTo(47.99530, 1e-9));
      expect(loaded.target.longitude, closeTo(37.81157, 1e-9));
      expect(loaded.zoom, 14.5);
      expect(loaded.bearing, 30);
    });

    test('a corrupt saved value loads as null instead of throwing', () async {
      FlutterSecureStorage.setMockInitialValues({'map_camera': 'not json'});
      expect(await SecureMapCameraStore().load(), isNull);
    });
  });

  group('shouldPersistCamera', () {
    test('never persists the untouched startup view', () {
      expect(shouldPersistCamera(initialMapCamera, cameraRestored: false), isFalse);
    });

    test('persists a view the user moved to, even before any restore', () {
      expect(
        shouldPersistCamera(const CameraPosition(target: LatLng(48, 37.8), zoom: 12), cameraRestored: false),
        isTrue,
      );
    });

    test('persists any view once the camera was restored or centered', () {
      expect(shouldPersistCamera(initialMapCamera, cameraRestored: true), isTrue);
    });
  });
}
