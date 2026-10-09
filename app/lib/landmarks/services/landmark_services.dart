import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/composite/services/area_service.dart';
import 'package:app/landmarks/composite/services/composite_creation_service.dart';
import 'package:app/landmarks/composite/services/route_service.dart';
import 'package:app/landmarks/composite/services/set_service.dart';
import 'package:app/landmarks/composite/services/track_service.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/icons/icon_registry.dart';
import 'package:app/landmarks/import_export/export/export_service.dart';
import 'package:app/landmarks/import_export/import/import_service.dart';
import 'package:app/landmarks/import_export/registry/format_registry.dart';
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
    required this.compositeCreation,
    required this.setService,
    required this.routeService,
    required this.trackService,
    required this.areaService,
    required this.editMode,
    required this.calculator,
    required this.formatRegistry,
    required this.importService,
    required this.exportService,
  });

  final MarkerCreationService creation;
  final WaypointService waypoints;
  final MetadataEditor editor;
  final FolderService folders;
  final IconRegistry icons;
  final LandmarkRepository repository;
  final CompositeCreationService compositeCreation;
  final SetService setService;
  final RouteService routeService;
  final TrackService trackService;
  final AreaService areaService;

  /// Режим правки составных объектов (один на приложение).
  final EditModeController editMode;
  final CompositeCalculator calculator;

  /// Форматы импорта/экспорта и сервисы над ними.
  final FormatRegistry formatRegistry;
  final ImportService importService;
  final ExportService exportService;

  /// Собирает сервисы: пути, базовые папки, репозиторий, настройки,
  /// реестр иконок (сразу просканированный), сервисы составных объектов
  /// и режим правки. [paths], [prefs] и [clock]
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
    const calculator = CompositeCalculator();
    final setService = SetService(repository, editor: editor, calculator: calculator);
    final routeService = RouteService(repository, editor: editor, calculator: calculator);
    final trackService = TrackService(repository, editor: editor, calculator: calculator);
    final areaService = AreaService(repository, editor: editor, calculator: calculator);
    final formats = FormatRegistry.buildDefault();
    return LandmarkServices(
      creation: MarkerCreationService(repository, folders, clock: clock),
      waypoints: WaypointService(repository, editor: editor),
      editor: editor,
      folders: folders,
      icons: icons,
      repository: repository,
      compositeCreation: CompositeCreationService(repository, folders, editor, calculator: calculator, clock: clock),
      setService: setService,
      routeService: routeService,
      trackService: trackService,
      areaService: areaService,
      editMode: EditModeController(
        setService: setService,
        routeService: routeService,
        trackService: trackService,
        areaService: areaService,
      ),
      calculator: calculator,
      formatRegistry: formats,
      importService: ImportService(repository, folders, formats, editor, calculator: calculator, clock: clock),
      exportService: ExportService(repository, folders, formats, clock: clock),
    );
  }
}
