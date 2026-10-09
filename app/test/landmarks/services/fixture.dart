import 'dart:io';

import 'package:app/intents/tracker_intent.dart';
import 'package:app/landmarks/explorer/places/places_provider.dart';
import 'package:app/storage/permission_service.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервисы меток во временной папке с подменённым временем.
class ServicesFixture {
  ServicesFixture._(this.root, this.paths, this.services, this._now);

  final Directory root;
  final StoragePaths paths;
  final LandmarkServices services;
  final List<DateTime> _now;

  DateTime get now => _now.single;
  set now(DateTime value) => _now[0] = value;

  static Future<ServicesFixture> create({
    TrackerService tracker = const LoggingTrackerService(),
    PlacesProvider Function(StoragePaths paths)? places,
    PermissionService? permissions,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('landmark_services_');
    final paths = StoragePaths.forRoot(root.path);
    final now = [DateTime.fromMillisecondsSinceEpoch(1760000000000)];
    final services = await LandmarkServices.bootstrap(
      paths: paths,
      prefs: await SharedPreferences.getInstance(),
      clock: () => now.single,
      trackerService: tracker,
      placesProvider: places?.call(paths),
      permissionService: permissions,
    );
    return ServicesFixture._(root, paths, services, now);
  }

  void dispose() => root.deleteSync(recursive: true);
}
