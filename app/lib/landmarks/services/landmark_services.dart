import 'package:app/app_settings/app_settings_controller.dart';
import 'package:app/backup/backup_service.dart';
import 'package:app/backup/restore_service.dart';
import 'package:app/dashboard/dashboard_controller.dart';
import 'package:app/derived_export/details_text_exporter.dart';
import 'package:app/derived_export/profile_csv_exporter.dart';
import 'package:app/intents/intent_dispatcher.dart';
import 'package:app/intents/tracker_intent.dart';
import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/explorer/clipboard/landmarks_clipboard.dart';
import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/explorer/explorer_controller.dart';
import 'package:app/landmarks/explorer/operations/explorer_operations.dart';
import 'package:app/landmarks/explorer/places/places_provider.dart';
import 'package:app/landmarks/explorer/selection/selection_controller.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
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
import 'package:app/maps/calibration/calibration_controller.dart';
import 'package:app/maps/color/erase_color_controller.dart';
import 'package:app/maps/color/layer_color_controller.dart';
import 'package:app/maps/dem/dem_manager.dart';
import 'package:app/maps/favorite_sets/favorite_set_controller.dart';
import 'package:app/maps/favorite_sets/favorite_set_store.dart';
import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/maps/layer_stack/layer_stack_controller.dart';
import 'package:app/maps/offline/offline_area_controller.dart';
import 'package:app/maps/offline/offline_area_estimator.dart';
import 'package:app/maps/on_demand/aqx_registry.dart';
import 'package:app/maps/on_demand/aqx_store.dart';
import 'package:app/maps/registry/map_source_registry.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:app/navigation/follow_path/follow_path_controller.dart';
import 'package:app/navigation/follow_path/follow_path_signal.dart';
import 'package:app/navigation/measure/measure_controller.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:app/navigation/proximity/proximity_alert_controller.dart';
import 'package:app/navigation/proximity/proximity_alert_signal.dart';
import 'package:app/navigation/proximity/proximity_alert_store.dart';
import 'package:app/navigation/settings/navigation_settings.dart';
import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:app/navigation/signals/silent_signaler.dart';
import 'package:app/navigation/target/target_controller.dart';
import 'package:app/share/share_service.dart';
import 'package:app/workspace/workspace_controller.dart';
import 'package:app/workspace/workspace_store.dart';
import 'package:app/storage/permission_service.dart';
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
    required this.positionSource,
    required this.signaler,
    required this.navigationSettings,
    required this.targetController,
    required this.followPathController,
    required this.proximityController,
    required this.measureController,
    required this.mapSourceRegistry,
    required this.mapsSettings,
    required this.layerStack,
    required this.colorController,
    required this.eraseColorController,
    required this.favoriteSets,
    required this.fileMapScanner,
    required this.aqxRegistry,
    required this.calibrationController,
    required this.demManager,
    required this.offlineArea,
    required this.appSettingsController,
    required this.workspaceController,
    required this.displayRegistry,
    required this.backupService,
    required this.restoreService,
    required this.intentDispatcher,
    required this.detailsTextExporter,
    required this.profileCsvExporter,
    required this.dashboardController,
    required this.shareService,
    required this.paths,
    required this.storage,
    required this.permissionService,
    required this.placesProvider,
    required this.explorerController,
    required this.explorerOperations,
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

  /// Положение устройства и звук; до платформенных реализаций — заглушки.
  final PositionSource positionSource;
  final AudioSignaler signaler;
  final NavigationSettings navigationSettings;
  final TargetController targetController;
  final FollowPathController followPathController;
  final ProximityAlertController proximityController;
  final MeasureController measureController;

  /// Карты и слои.
  final MapSourceRegistry mapSourceRegistry;
  final MapsSettings mapsSettings;
  final LayerStackController layerStack;
  final LayerColorController colorController;
  final EraseColorController eraseColorController;
  final FavoriteSetController favoriteSets;
  final FileMapScanner fileMapScanner;
  final AqxRegistry aqxRegistry;
  final CalibrationController calibrationController;
  final DemManager demManager;
  final OfflineAreaController offlineArea;

  /// Общие настройки, пространства, копии, внешние запросы, экспорт,
  /// дашборд, отправка.
  final AppSettingsController appSettingsController;
  final WorkspaceController workspaceController;

  /// Метки на карте (общий для проводника и пространств).
  final DisplayRegistry displayRegistry;
  final BackupService backupService;
  final RestoreService restoreService;
  final IntentDispatcher intentDispatcher;
  final DetailsTextExporter detailsTextExporter;
  final ProfileCsvExporter profileCsvExporter;
  final DashboardController dashboardController;
  final ShareService shareService;

  /// Пути и файлы хранилища.
  final StoragePaths paths;
  final StorageService storage;

  /// Доступ к папкам вне папки приложения.
  final PermissionService permissionService;

  /// Проводник меток: разделы, контроллер, операции над файлами.
  final PlacesProvider placesProvider;
  final ExplorerController explorerController;
  final ExplorerOperations explorerOperations;

  /// Собирает сервисы: пути, базовые папки, репозиторий, настройки,
  /// реестр иконок (сразу просканированный), сервисы составных объектов
  /// и режим правки. [paths], [prefs] и [clock]
  /// подменяются в тестах.
  static Future<LandmarkServices> bootstrap({
    StoragePaths? paths,
    SharedPreferences? prefs,
    DateTime Function()? clock,
    PermissionService? permissionService,
    PlacesProvider? placesProvider,
    PositionSource positionSource = const StubPositionSource(),
    AudioSignaler signaler = const SilentSignaler(),
    ShareService shareService = const UnavailableShareService(),
    TrackerService trackerService = const LoggingTrackerService(),
  }) async {
    final storagePaths = paths ?? await StoragePaths.resolve();
    final storage = StorageService(storagePaths);
    await storage.migrateLegacyFolders();
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
    final navigation = NavigationSettings(settings);
    final waypoints = WaypointService(repository, editor: editor);
    final target = TargetController(
      positionSource,
      waypoints: waypoints,
      displayLine: navigation.targetDisplayLine,
      displayInfoBox: navigation.targetDisplayInfoBox,
    );
    final proximity = ProximityAlertController(
      ProximityAlertStore(settings),
      positionSource,
      signaler,
      target,
      emitter: ProximityAlertSignalEmitter(signaler, enabled: () => navigation.signalsEnabled),
    );
    await proximity.load(navigation.currentWorkspace);

    final maps = MapsSettings(settings);
    final mapSources = MapSourceRegistry.buildDefault();
    final layers = LayerStackController(maps);
    await layers.load();
    final favorites = FavoriteSetController(FavoriteSetStore(settings), layers, clock: clock);
    await favorites.loadAll();
    final scanner = FileMapScanner(storagePaths, registry: mapSources);
    await scanner.scanAll();
    final aqx = AqxRegistry(storagePaths, store: AqxStore(settings));
    await aqx.refresh();
    final dem = DemManager(storagePaths, maps.demSettings, store: maps);
    await dem.loadSettings();

    final appSettings = AppSettingsController(settings);
    await appSettings.load();
    final display = DisplayRegistry();
    final workspaces = WorkspaceController(
      WorkspaceStore(settings),
      layers,
      target,
      maps,
      navigation,
      display: display,
      proximity: proximity,
      clock: clock,
    );
    await workspaces.load();
    final creation = MarkerCreationService(repository, folders, clock: clock);
    final reader = LandmarkItemReader(storage);
    final places = placesProvider ?? PlacesProvider(storagePaths);
    final clipboard = LandmarksClipboard();
    return LandmarkServices(
      creation: creation,
      waypoints: waypoints,
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
      positionSource: positionSource,
      signaler: signaler,
      navigationSettings: navigation,
      targetController: target,
      followPathController: FollowPathController(
        trackService,
        positionSource,
        signaler,
        FollowPathSignalEmitter(signaler, enabled: () => navigation.signalsEnabled),
      ),
      proximityController: proximity,
      measureController: MeasureController(),
      mapSourceRegistry: mapSources,
      mapsSettings: maps,
      layerStack: layers,
      colorController: const LayerColorController(),
      eraseColorController: const EraseColorController(),
      favoriteSets: favorites,
      fileMapScanner: scanner,
      aqxRegistry: aqx,
      calibrationController: CalibrationController(maps),
      demManager: dem,
      offlineArea: OfflineAreaController(const OfflineAreaEstimator(), storage),
      appSettingsController: appSettings,
      workspaceController: workspaces,
      displayRegistry: display,
      backupService: BackupService(storagePaths, storage, settings, clock: clock),
      restoreService: RestoreService(storagePaths, storage, settings),
      intentDispatcher: IntentDispatcher(creation, target, folders, trackerService),
      detailsTextExporter: DetailsTextExporter(storagePaths, storage, locale: () => appSettings.model.locale),
      profileCsvExporter: ProfileCsvExporter(storagePaths, storage),
      dashboardController: DashboardController(reader),
      shareService: shareService,
      paths: storagePaths,
      storage: storage,
      permissionService: permissionService ?? WriteCheckPermissionService(storage),
      placesProvider: places,
      explorerController: ExplorerController(
        folders: folders,
        places: places,
        reader: reader,
        displayRegistry: display,
        selection: SelectionController(),
        clipboard: clipboard,
        settings: settings,
      ),
      explorerOperations: ExplorerOperations(
        repository: repository,
        reader: reader,
        storage: storage,
        clipboard: clipboard,
        display: display,
        editor: editor,
      ),
    );
  }
}
