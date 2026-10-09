import 'dart:io';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Временное хранилище меток для тестов проводника.
class ExplorerFixture {
  ExplorerFixture._(this.root, this.paths, this.storage, this.repository, this.reader, this.settings);

  final Directory root;
  final StoragePaths paths;
  final StorageService storage;
  final LandmarkRepository repository;
  final LandmarkItemReader reader;
  final AppSettings settings;

  static Future<ExplorerFixture> create() async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('explorer_');
    final paths = StoragePaths.forRoot(root.path);
    final storage = StorageService(paths);
    await storage.ensureBaseFolders();
    final repository = LandmarkRepository(storage, paths, clock: () => DateTime.fromMillisecondsSinceEpoch(1760000000000));
    return ExplorerFixture._(
      root,
      paths,
      storage,
      repository,
      LandmarkItemReader(storage),
      AppSettings(await SharedPreferences.getInstance()),
    );
  }

  /// Сохраняет путевую точку и возвращает путь.
  Future<String> waypoint(
    String name, {
    double lat = 50.45,
    double lon = 30.52,
    int? color,
    String? icon,
    String? directory,
    Map<String, Object> extra = const {},
  }) => repository.save(
    LandmarkFile.of(
      WaypointObject(
        location: LandmarkLocation(longitude: lon, latitude: lat),
        userMetadata: LandmarkMetadata(
          entries: {'name': name, 'color': ?color, 'icon': ?icon, ...extra},
        ),
      ),
    ),
    directory: directory,
  );

  /// Сохраняет трек с метаданными [extra] и возвращает путь.
  Future<String> track(String name, {Map<String, Object> extra = const {}, String? directory}) => repository.save(
    LandmarkFile.of(
      TrackObject(
        userMetadata: LandmarkMetadata(entries: {'name': name, ...extra}),
        segments: const [
          TrackSegment(
            locations: [
              LandmarkLocation(longitude: 30, latitude: 50),
              LandmarkLocation(longitude: 30.1, latitude: 50.1),
            ],
          ),
        ],
      ),
    ),
    directory: directory,
  );

  void dispose() => root.deleteSync(recursive: true);
}

/// Элемент списка без файла — для тестов сортировки, фильтра, статистики.
LandmarkItem item(
  String name, {
  LandmarkType type = LandmarkType.track,
  int createdAt = 0,
  double? lat,
  double? lon,
  double? length,
  int? duration,
  double? gain,
  double? area,
  String? activity,
  int? year,
}) => LandmarkItem(
  path: '/x/$name.${type.extension}',
  name: name,
  type: type,
  colorValue: LandmarkItem.defaultColor,
  createdAt: createdAt,
  updatedAt: createdAt,
  fileSizeBytes: 1,
  fileModifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
  latitude: lat,
  longitude: lon,
  lengthMeters: length,
  durationMs: duration,
  elevationGainMeters: gain,
  areaSquareMeters: area,
  activity: activity,
  year: year,
);
