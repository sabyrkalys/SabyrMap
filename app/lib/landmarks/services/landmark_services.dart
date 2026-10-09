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

  /// Собирает сервисы: пути, базовые папки, репозиторий, настройки,
  /// реестр иконок (сразу просканированный), сервисы составных объектов
  /// и режим правки. [paths], [prefs] и [clock]
  /// подменяются в тестах.
  static Future<LandmarkServices> bootstrap({
    StoragePaths? paths,
    SharedPreferences? prefs,
    DateTime Function()? clock,
    PositionSource positionSource = const StubPositionSource(),
    AudioSignaler signaler = const SilentSignaler(),
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
    return LandmarkServices(
      creation: MarkerCreationService(repository, folders, clock: clock),
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
    );
  }
}
