import 'package:app/landmarks/icons/icon_registry.dart';
import 'package:app/landmarks/icons/icon_resolver.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folder_service.dart';
import 'marker_creation_service.dart';
import 'metadata_editor.dart';
import 'waypoint_service.dart';

/// Сервисы меток для UI, собранные вручную, без DI-пакетов.
class LandmarkServices {
  const LandmarkServices({
    required this.creation,
    required this.waypoints,
    required this.editor,
    required this.folders,
    required this.icons,
    required this.repository,
  });

  final MarkerCreationService creation;
  final WaypointService waypoints;
  final MetadataEditor editor;
  final FolderService folders;
  final IconRegistry icons;
  final LandmarkRepository repository;

  /// Собирает сервисы: пути, базовые папки, репозиторий, настройки,
  /// реестр иконок (сразу просканированный). [paths], [prefs] и [clock]
  /// подменяются в тестах.
  static Future<LandmarkServices> bootstrap({
    StoragePaths? paths,
    SharedPreferences? prefs,
    DateTime Function()? clock,
  }) async {
    final storagePaths = paths ?? await StoragePaths.resolve();
    final storage = StorageService(storagePaths);
    await storage.ensureBaseFolders();
    final repository = LandmarkRepository(storage, storagePaths, clock: clock);
    final settings = AppSettings(prefs ?? await SharedPreferences.getInstance());
    final icons = IconRegistry(IconResolver(storagePaths));
    await icons.refresh();
    final folders = FolderService(storagePaths, settings);
    final editor = MetadataEditor(clock: clock);
    return LandmarkServices(
      creation: MarkerCreationService(repository, folders, clock: clock),
      waypoints: WaypointService(repository, editor: editor),
      editor: editor,
      folders: folders,
      icons: icons,
      repository: repository,
    );
  }
}
