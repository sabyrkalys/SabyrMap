import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/landmark_services_provider.dart';
import '../explorer/item_menu/item_context_menu.dart';
import '../landmarks/index/landmark_index.dart';
import '../landmarks/composite/edit_mode/edit_mode_controller.dart';
import '../landmarks/models/landmark_file.dart';
import '../landmarks/on_screen/on_screen_registry.dart';
import '../config.dart';
import '../icons/icon_image_cache.dart';
import '../icons/icon_library_scanner.dart';
import 'attribution_bar.dart';
import 'models/map_models.dart';
import 'catalog/catalog_repository.dart';
import 'crosshair_menu.dart';
import 'drawing/drawing_actions.dart';
import 'drawing/drawing_bar.dart';
import 'drawing/set_panel.dart';
import 'drawing/shape_dialogs.dart';
import 'info_panel.dart';
import 'landmark_layer.dart';
import 'map_camera_store.dart';
import 'map_crosshair.dart';
import 'map_overlays.dart';
import 'map_scale.dart';
import '../icons/icon_renderer.dart';
import '../app_icons.dart';
import '../widgets/app_icon.dart';
import 'map_focus.dart';
import 'orthophoto/orthophoto_extent.dart';
import 'map_target.dart';
import 'point_info_sheet.dart';
import 'prefetch/neighbor_prefetcher.dart';
import 'services/google_tiles_service.dart';
import 'services/layer_manager.dart';
import 'services/style_cache.dart';
import 'services/maplibre_layer_host.dart';
import 'services/yandex_tiles_service.dart';
import 'state/map_layers_controller.dart';
import 'state/map_viewport.dart';
import '../menu/menu_toggles.dart';
import '../tracks/track_models.dart';
import '../tracks/track_recording_controller.dart';
import '../waypoints/waypoint_actions.dart';
import '../waypoints/waypoint_create_action.dart';

const String _recordingLineKey = '__recording__';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;

  // Loading bar: on from a camera move or style load until MapLibre reports
  // the map idle (everything visible is drawn).
  bool _mapBusy = false;
  bool _prefetchConfigured = false;
  static const _mapChannel = MethodChannel('sabyrmap/map');
  // Метки из индекса — слоем стиля карты (LandmarkLayer). Перерисовка —
  // только когда метки или их видимость менялись: запись трека тоже идёт
  // через общий _requestSync, и без флага каждая точка GPS заново
  // отправляла бы на карту все метки.
  LandmarkLayer? _landmarkLayer;
  bool _landmarksDirty = true;
  late final LandmarkIndex _landmarkIndex;

  // Рисование нового маршрута или области: панель над картой, точки — в
  // прицел, черновик — своим источником LandmarkLayer.
  late final EditModeController _editMode;

  final Map<String, Line> _linesByTrackId = {};
  // A cheap "did this actually change" key per line id, so _syncLines only
  // issues an updateLine platform call when the geometry differs from what
  // is already applied (the recording stream requests a sync on every
  // recorded GPS point).
  final Map<String, String> _appliedLineKeys = {};

  late final IconImageCache _iconImageCache = IconImageCache(
    addImage: (name, bytes) async {
      final controller = _controller;
      if (controller == null) return;
      await controller.addImage(name, bytes);
    },
    // Rendered in physical pixels for this screen (see kIconLogicalSize).
    render: (icon, colorHex) =>
        renderIconBytes(icon, colorHex, size: iconCanvasPixels(View.of(context).devicePixelRatio), glow: true),
  );
  final IconLibraryScanner _iconLibraryScanner = IconLibraryScanner();
  // Cached so a landmark sync doesn't rescan the device folder for every
  // icon. A file name that isn't in the map triggers exactly
  // one rescan (the user may have dropped a new file in while the app was
  // running); if it's still missing afterwards it's recorded in
  // _unresolvableIconFileNames so a file that was deleted from the device
  // doesn't cause a folder listing on every subsequent sync.
  final Map<String, IconFile> _iconFilesByFileName = {};
  final Set<String> _unresolvableIconFileNames = {};
  bool _iconFilesLoaded = false;

  // One-shot "my location" state: fetched once on screen open, not a live
  // feed. _hasCenteredCamera guards animateCamera so a later style reload
  // (which re-runs _onStyleLoaded) never re-centers the map out from under
  // the user after they've since panned away.
  TrackPoint? _myLocation;
  Circle? _myLocationCircle;
  bool _hasCenteredCamera = false;

  // The last view saved on the device. When present the map reopens there
  // instead of centering on GPS; _savedCameraLoaded holds back any
  // centering until the read has finished, so GPS can't win the race.
  CameraPosition? _savedCamera;
  bool _savedCameraLoaded = false;

  // Crosshair coordinate readout: refreshed whenever the camera settles
  // (not on every drag frame, to avoid rebuilding the HUD on each pixel of
  // a pan gesture).
  LatLng? _crosshairPosition;
  double _cameraZoom = initialMapCamera.zoom;

  // Live camera centre, tracked only while a target is set so the distance
  // label follows a drag without rebuilding on every frame otherwise.
  LatLng? _liveCenter;
  // Live camera for the «Задать цель» distance plate beside the crosshair
  // (the line and dot themselves are MainActivity's TargetLine).
  final ValueNotifier<CameraPosition?> _liveCamera = ValueNotifier(null);
  // Crosshair position for the info panel's X/Y, every camera frame. A
  // notifier, so only the panel rebuilds while the map moves.
  final ValueNotifier<LatLng?> _panelCenter = ValueNotifier(null);

  // Serializes map syncs: at most one runs at a time, and any state change
  // that arrives while a run is in flight is coalesced into a single
  // trailing re-run (rather than racing concurrently against the in-flight
  // one, which could orphan or duplicate lines).
  bool _isSyncing = false;
  bool _syncPending = false;

  // Captured in initState rather than read directly inside dispose(): by the
  // time State.dispose() runs, the widget's element is already deactivated
  // and using `ref` throws ("Using ref when a widget is about to or has
  // been unmounted is unsafe"). The notifier instance itself is stable for
  // the lifetime of the (root-scope, non-autoDispose) provider, so grabbing
  // it once up front and calling stop() on it later is safe.
  late final TrackRecordingController _recordingController;

  // «Метки на экране»: скрытая глазом или убранная метка не рисуется.
  late final OnScreenRegistry _onScreen;

  @override
  void initState() {
    super.initState();
    _recordingController = ref.read(trackRecordingControllerProvider.notifier);
    _onScreen = ref.read(onScreenRegistryProvider)..addListener(_onLandmarksChanged);
    _landmarkIndex = ref.read(landmarkServicesProvider).index..addListener(_onLandmarksChanged);
    _editMode = ref.read(landmarkServicesProvider).editMode..addListener(_onEditModeChanged);
    _loadSavedCamera();
    _loadMyLocation();
  }

  // A failed read is a soft failure: the map just falls back to GPS
  // centering, same as on a first launch.
  Future<void> _loadSavedCamera() async {
    try {
      _savedCamera = await ref.read(mapCameraStoreProvider).load();
    } catch (_) {}
    if (!mounted) return;
    _savedCameraLoaded = true;
    _maybeCenterCamera();
  }

  // Fetches the device's current position once, for centering the map and
  // showing a "my location" dot. GPS being unavailable or permission being
  // denied is a normal, silent outcome here (the map just stays as-is) --
  // any exception from the platform channel (e.g. no location plugin
  // registered, as in widget tests) is swallowed for the same reason.
  Future<void> _loadMyLocation() async {
    try {
      final position = await ref.read(locationSourceProvider).getCurrentPosition();
      if (!mounted || position == null) return;
      _myLocation = position;
      _maybeCenterCamera();
      _requestSync();
    } catch (_) {
      // No GPS available -- leave the map exactly as it is.
    }
  }

  void _maybeCenterCamera() {
    if (_hasCenteredCamera || !_savedCameraLoaded) return;
    final controller = _controller;
    if (controller == null) return;
    final saved = _savedCamera;
    if (saved != null) {
      _hasCenteredCamera = true;
      controller.moveCamera(CameraUpdate.newCameraPosition(saved));
      return;
    }
    final location = _myLocation;
    if (location == null) return;
    _hasCenteredCamera = true;
    controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(location.lat, location.lng), 15));
  }

  @override
  void dispose() {
    _onScreen.removeListener(_onLandmarksChanged);
    _landmarkIndex.removeListener(_onLandmarksChanged);
    _editMode.removeListener(_onEditModeChanged);
    // trackRecordingControllerProvider is a root-scope, non-autoDispose
    // provider: it survives MapScreen being swapped out (e.g. on logout),
    // so without this the geolocator stream would keep appending points in
    // the background and a subsequent user could pick up and save the
    // previous user's still-in-progress recording. stop() is synchronous
    // and a no-op when already idle.
    //
    // Riverpod forbids modifying provider state synchronously from within a
    // widget's dispose() (the element tree is locked while unmounting), so
    // the call is deferred to a microtask, which runs immediately after
    // this frame finishes finalizing. If the whole provider container is
    // also being torn down around the same time (e.g. app shutdown, test
    // teardown), the notifier's Ref may already be disposed by the time the
    // microtask runs; that's fine since there's no container left in which
    // a leaked recording could resurface, so the resulting exception is
    // swallowed.
    Future.microtask(() {
      try {
        _recordingController.stop();
      } catch (_) {}
    });
    _panelCenter.dispose();
    _liveCamera.dispose();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _landmarkLayer = LandmarkLayer(controller);
    controller.onFeatureTapped.add(_onFeatureTapped);
    ref.read(mapViewportProvider.notifier).register(() async {
      final c = _controller;
      if (c == null) return null;
      return (bounds: await c.getVisibleRegion(), zoom: c.cameraPosition?.zoom ?? _cameraZoom);
    });
  }

  // Base maps and overlays («Доступные карты», «Карты на экране»). The
  // manager is attached once the first style has loaded (annotation layers
  // exist then); the host is told about every later style load so a base
  // change can wait for it.
  MapLibreLayerHost? _layerHost;
  bool _layersAttached = false;

  Future<void> _attachLayers(MapLibreMapController controller) async {
    final host = _layerHost = MapLibreLayerHost(controller);
    final List<MapProvider> providers;
    try {
      providers = await ref.read(catalogProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final manager = LayerManager(
      host: host,
      catalog: LayerCatalog(providers),
      google: ref.read(googleTilesServiceProvider),
      yandex: ref.read(yandexTilesServiceProvider),
      fetchText: ref.read(styleCacheProvider).fetch,
    );
    final result = await ref.read(mapLayersProvider.notifier).attach(manager);
    if (!result.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.problems.join('\n'))));
    }
    await _updateOrthophotos();
  }

  /// Кнопка ортофотопланов: включить или выключить.
  Future<void> _toggleOrthophotos() async {
    final notifier = ref.read(mapLayersProvider.notifier);
    final on = !ref.read(mapLayersProvider).orthophotosOn;
    final files = await notifier.setOrthophotosOn(on);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (on && files == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ортофотопланов нет: положите файлы .mbtiles в папку mediafile/orthophoto')),
      );
      return;
    }
    // Включённые ортофотопланы ставит на карту ref.listen в build.
  }

  /// Ортофотопланы вокруг экрана (видимая область и соседние участки) — на
  /// карту, остальные — с карты. Вызывается после каждой остановки камеры.
  Future<void> _updateOrthophotos() async {
    final controller = _controller;
    final zoom = controller?.cameraPosition?.zoom;
    if (controller == null || zoom == null || !ref.read(mapLayersProvider).orthophotosOn) return;
    try {
      final visible = await controller.getVisibleRegion();
      final result = await ref.read(mapLayersProvider.notifier).updateOrthophotos(
        GeoBox(
          west: visible.southwest.longitude,
          south: visible.southwest.latitude,
          east: visible.northeast.longitude,
          north: visible.northeast.latitude,
        ),
        zoom,
      );
      if (!result.ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.problems.join('\n'))));
      }
    } catch (_) {
      // Карта ещё не готова или уже закрыта: следующая остановка повторит.
    }
  }

  // Driven by MapLibreMap.onCameraMove, not a controller listener: the
  // controller also notifies its listeners after every add/update/removeLine,
  // so listening there made each line update trigger the next one forever.
  //
  // The zoom feeds the info panel's scale readout during a pinch; to avoid a
  // rebuild on every frame it is only applied once it moved by 0.1 or more.
  void _onCameraMove(CameraPosition position) {
    _panelCenter.value = position.target;
    _liveCamera.value = position;
    if (!_mapBusy) {
      if (mounted) setState(() => _mapBusy = true);
      ref.read(neighborPrefetcherProvider).cancel();
    }
    final zoomChanged = (position.zoom - _cameraZoom).abs() >= 0.1;
    final hasTarget = ref.read(mapTargetProvider).point != null;
    if (!zoomChanged && !hasTarget) return;
    if (mounted) {
      setState(() {
        if (zoomChanged) _cameraZoom = position.zoom;
        if (hasTarget) _liveCenter = position.target;
      });
    }
  }

  // The crosshair watches raw pointers without taking part in gestures, so
  // drags and pinches that start on it still reach the map. A short,
  // single-finger tap that doesn't move opens or closes the card; this works
  // even when the map style (and with it MapLibre's own tap handling) has
  // not loaded.
  static const Duration _crosshairTapTimeout = Duration(milliseconds: 500);
  final Map<int, (Offset, Duration)> _crosshairPointers = {};
  bool _crosshairMultiTouch = false;

  void _onCrosshairPointerDown(PointerDownEvent event) {
    _crosshairPointers[event.pointer] = (event.position, event.timeStamp);
    if (_crosshairPointers.length > 1) _crosshairMultiTouch = true;
  }

  void _onCrosshairPointerUp(PointerUpEvent event) {
    final down = _crosshairPointers.remove(event.pointer);
    final multiTouch = _crosshairMultiTouch;
    if (_crosshairPointers.isEmpty) _crosshairMultiTouch = false;
    if (down == null || multiTouch) return;
    final (position, time) = down;
    if ((event.position - position).distance > kTouchSlop) return;
    if (event.timeStamp - time > _crosshairTapTimeout) return;
    // Пока рисуется маршрут или область, нажатие на прицел ставит точку.
    if (_drawing) {
      _addDrawingPoint();
      return;
    }
    ref.read(crosshairMenuOpenProvider.notifier).toggle();
  }

  void _onCrosshairPointerCancel(PointerCancelEvent event) {
    _crosshairPointers.remove(event.pointer);
    if (_crosshairPointers.isEmpty) _crosshairMultiTouch = false;
  }

  /// The «Задать цель» line and dot are drawn natively (MainActivity's
  /// TargetLine), which moves the line's crosshair end with the map in the
  /// same frame. Hidden with «Линия к цели» off.
  Future<void> _syncTarget() async {
    final target = ref.read(mapTargetProvider).point;
    final show = target != null && ref.read(menuTogglesProvider)[MenuToggle.waypointsTargetLine]!;
    try {
      await _mapChannel.invokeMethod<int>('setTarget', {
        if (show) 'lat': target.latitude,
        if (show) 'lng': target.longitude,
      });
    } catch (_) {
      // Not on Android (tests, other platforms).
    }
  }

  void _onMapIdle() {
    if (_mapBusy && mounted) setState(() => _mapBusy = false);
  }

  /// Loads the neighbourhood of what is on screen into the tile cache.
  Future<void> _prefetchAround(double zoom) async {
    final controller = _controller;
    if (controller == null) return;
    final LatLngBounds visible;
    try {
      visible = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final baseId = ref.read(mapLayersProvider).baseSourceId ?? CatalogRepository.defaultBaseSourceId;
    MapSource? base;
    for (final provider in ref.read(catalogProvider).value ?? const <MapProvider>[]) {
      for (final source in provider.sources) {
        if (source.id == baseId) base = source;
      }
    }
    await ref.read(neighborPrefetcherProvider).onIdle(
          source: base,
          visible: visible,
          zoom: zoom,
          recording: ref.read(trackRecordingControllerProvider) is TrackRecordingActive,
        );
  }

  /// Tiles 4 zooms below the current one load first, so a zoom-out or a
  /// fast pan shows a coarse map instead of blank squares.
  Future<void> _configurePrefetch() async {
    if (_prefetchConfigured) return;
    _prefetchConfigured = true;
    try {
      await _mapChannel.invokeMethod<int>('setPrefetchZoomDelta', {'delta': 4});
    } catch (_) {
      // Not on Android (tests, other platforms): MapLibre's default stays.
    }
    await ref.read(neighborPrefetcherProvider).cleanUpLeftovers();
  }

  void _onCameraIdle() {
    final position = _controller?.cameraPosition;
    if (position == null) return;
    _prefetchAround(position.zoom);
    _panelCenter.value = position.target;
    _liveCamera.value = position;
    setState(() {
      _crosshairPosition = position.target;
      _cameraZoom = position.zoom;
    });
    ref.read(mapCrosshairProvider.notifier).set(position.target);
    unawaited(_updateOrthophotos());
    if (_savedCameraLoaded && shouldPersistCamera(position, cameraRestored: _hasCenteredCamera)) {
      ref.read(mapCameraStoreProvider).save(position).catchError((_) {});
    }
  }

  Future<void> _onStyleLoaded() async {
    _layerHost?.notifyStyleLoaded();
    if (mounted && !_mapBusy) setState(() => _mapBusy = true);
    _configurePrefetch();
    final controller = _controller;
    if (!_layersAttached && controller != null) {
      _layersAttached = true;
      _attachLayers(controller);
    }
    // Every style (re)load disposes and re-creates maplibre_gl's annotation
    // managers, which wipes their internal id tracking. Drop our own
    // tracking too so the next sync re-adds every line from scratch instead
    // of trying to update ids the new manager doesn't know about. Images
    // registered against the old style, and the landmark source and layers,
    // are gone as well.
    _linesByTrackId.clear();
    _appliedLineKeys.clear();
    _iconImageCache.clear();
    _myLocationCircle = null;
    _landmarkLayer?.detach();
    _landmarksDirty = true;
    // Wrapped in try/catch since this callback is invoked fire-and-forget by
    // maplibre_gl (no await, no error handler upstream): an unguarded throw
    // here (e.g. a style-reload/dispose race) would both surface as an
    // unhandled async error and skip _maybeCenterCamera()/_requestSync()
    // below, silently leaving the map empty.
    try {
      await _landmarkLayer?.attach();
    } catch (_) {}
    unawaited(_syncDraft());
    _maybeCenterCamera();
    _requestSync();
    _syncTarget();
  }

  /// Рисуется новый маршрут или область (не правка существующего).
  bool get _drawing => _editMode.state.target?.isNew ?? false;

  void _onEditModeChanged() {
    if (mounted) setState(() {});
    unawaited(_syncDraft());
  }

  Future<void> _syncDraft() async {
    try {
      await _landmarkLayer?.updateDraft(
        _drawing ? _editMode.state.target!.object : ref.read(drawingPreviewProvider),
      );
    } catch (_) {
      // Карта ещё не готова: черновик поставит следующая загрузка стиля.
    }
  }

  /// Точка в прицел — та, что под ним сейчас, а не при последней остановке.
  void _addDrawingPoint() {
    final center = _controller?.cameraPosition?.target ?? ref.read(mapCrosshairProvider);
    if (center == null) return;
    _editMode.addPoint(LandmarkLocation(latitude: center.latitude, longitude: center.longitude));
  }

  void _onLandmarksChanged() {
    _landmarksDirty = true;
    _requestSync();
  }

  /// Entry point for requesting a combined landmarks+line sync. Coalesces
  /// concurrent requests so only one sync run is ever in flight; [_runSync]
  /// reads fresh state via `ref.read` when it actually runs, rather than
  /// being handed a snapshot up front.
  void _requestSync() {
    if (_isSyncing) {
      _syncPending = true;
      return;
    }
    _runSync();
  }

  Future<void> _runSync() async {
    _isSyncing = true;
    try {
      await _syncLandmarks();
      await _syncLines();
      await _syncMyLocationCircle();
    } catch (_) {
      // Swallow sync failures (e.g. a manager wasn't ready yet, or a style
      // reload raced with an in-flight call): the next state change or
      // style-loaded event will retry from a clean slate.
    } finally {
      _isSyncing = false;
    }
    if (_syncPending) {
      _syncPending = false;
      _requestSync();
    }
  }

  /// Метки из индекса — на карту. Скрытые и убранные в «Метках на экране»
  /// не рисуются: скрыт файл — скрыты и объекты внутри него.
  Future<void> _syncLandmarks() async {
    final layer = _landmarkLayer;
    if (!_landmarksDirty || layer == null || !layer.isAttached) return;
    _landmarksDirty = false;
    final services = ref.read(landmarkServicesProvider);
    final items = [
      for (final item in services.index.items)
        if (_onScreen.isVisible(item.filePath) && _onScreen.isVisible(item.path)) item,
    ];
    try {
      final features = await services.geometry.featuresOf(items);
      services.geometry.retainOnly(services.index.items.map((i) => i.filePath));
      await layer.update(features, _landmarkIconImage);
    } catch (_) {
      _landmarksDirty = true;
      rethrow;
    }
  }

  /// Картинка значка [fileName] цвета [colorHex] в стиле карты; null —
  /// файла значка на устройстве нет.
  Future<String?> _landmarkIconImage(String fileName, String colorHex) async {
    final iconFile = await _resolveIconFile(fileName);
    return iconFile == null ? null : _iconImageCache.resolve(iconFile, colorHex);
  }

  /// Resolves an assigned icon file name  /// Resolves an assigned icon file name to the [IconFile] describing it,
  /// scanning the device folder at most once per unresolvable name (see
  /// [_iconFilesByFileName]). Returns null when no such file exists.
  Future<IconFile?> _resolveIconFile(String fileName) async {
    final cached = _iconFilesByFileName[fileName];
    if (cached != null) return cached;
    if (_iconFilesLoaded && _unresolvableIconFileNames.contains(fileName)) return null;

    final files = await _iconLibraryScanner.scan();
    _iconFilesByFileName
      ..clear()
      ..addEntries(files.map((f) => MapEntry(f.fileName, f)));
    _iconFilesLoaded = true;
    final resolved = _iconFilesByFileName[fileName];
    if (resolved == null) _unresolvableIconFileNames.add(fileName);
    return resolved;
  }

  Future<void> _syncLines() async {
    final controller = _controller;
    // Same readiness guard as _syncCircles, for the line manager.
    if (controller == null || controller.lineManager == null) return;
    // Same stale-manager reconciliation as _syncCircles, for lines. This is
    // more reachable here than for circles: the recording stream can emit
    // a new point (and thus request a sync) far more often than waypoints
    // change, so the window between a style reload creating a new line
    // manager and onStyleLoadedCallback clearing our tracking is more
    // likely to be hit mid-flight.
    final liveLineIds = controller.lines.map((l) => l.id).toSet();
    _linesByTrackId.removeWhere((id, line) {
      final stale = !liveLineIds.contains(line.id);
      if (stale) _appliedLineKeys.remove(id);
      return stale;
    });

    // Сохранённые треки — файлы меток, их рисует LandmarkLayer; здесь —
    // только линия идущей записи.
    final recordingState = ref.read(trackRecordingControllerProvider);
    if (recordingState is TrackRecordingActive && recordingState.points.length >= 2) {
      final key = _geometryKey(recordingState.points.map((p) => (p.lat, p.lng)).toList());
      final existing = _linesByTrackId[_recordingLineKey];
      if (existing == null) {
        final options = LineOptions(
          geometry: [for (final p in recordingState.points) LatLng(p.lat, p.lng)],
          lineColor: '#E53935',
          lineWidth: 4,
        );
        _linesByTrackId[_recordingLineKey] = await controller.addLine(options);
        _appliedLineKeys[_recordingLineKey] = key;
      } else if (_appliedLineKeys[_recordingLineKey] != key) {
        final options = LineOptions(
          geometry: [for (final p in recordingState.points) LatLng(p.lat, p.lng)],
          lineColor: '#E53935',
          lineWidth: 4,
        );
        await controller.updateLine(existing, options);
        _appliedLineKeys[_recordingLineKey] = key;
      }
    } else {
      final existing = _linesByTrackId.remove(_recordingLineKey);
      _appliedLineKeys.remove(_recordingLineKey);
      if (existing != null) {
        await controller.removeLine(existing);
      }
    }
  }

  /// Renders the one-shot "my location" dot. Unlike waypoint/track circles
  /// this never needs an updateCircle call -- _myLocation is fetched once
  /// and never changes for the lifetime of the screen -- so once added, the
  /// only thing that can invalidate it is a style reload (handled by
  /// clearing _myLocationCircle in _onStyleLoaded so it's re-added fresh).
  Future<void> _syncMyLocationCircle() async {
    final controller = _controller;
    if (controller == null || controller.circleManager == null) return;
    if (_myLocationCircle != null) return;
    final location = _myLocation;
    if (location == null) return;
    _myLocationCircle = await controller.addCircle(
      CircleOptions(
        geometry: LatLng(location.lat, location.lng),
        circleRadius: 7,
        circleColor: '#2196F3',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
  }

  /// Cheap proxy key for "did this line's geometry change": point count
  /// plus the last point's coordinates. Not a full geometry comparison, but
  /// sufficient to skip redundant updateLine calls for tracks/recordings
  /// whose points haven't changed since the last sync.
  String _geometryKey(List<(double, double)> points) {
    if (points.isEmpty) return '0';
    final last = points.last;
    return '${points.length}|${last.$1}|${last.$2}';
  }

  /// Нажатие по метке: у путевой точки — её карточка, у остальных — меню
  /// метки, как в «Всех метках».
  void _onFeatureTapped(Point<double> point, LatLng coordinates, String id, String layerId, Annotation? annotation) {
    final path = _landmarkLayer?.pathOf(id, layerId);
    if (path == null) return;
    final item = _landmarkIndex.byPath(path);
    if (item == null || !mounted) return;
    if (item.type == LandmarkType.waypoint) {
      showWaypointDetails(context, ref, item);
    } else {
      ItemContextMenu.show(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orthophotosOn = ref.watch(mapLayersProvider.select((state) => state.orthophotosOn));
    ref.listen<TrackRecordingState>(trackRecordingControllerProvider, (previous, next) {
      _requestSync();
    });
    // Ортофотопланы включают кнопка и глазик в «Картах на экране».
    ref.listen<bool>(mapLayersProvider.select((state) => state.orthophotosOn), (previous, next) {
      if (next && previous == false) unawaited(_updateOrthophotos());
    });

    // Круг из диалога «Круг» — черновиком, пока выбирается радиус.
    ref.listen(drawingPreviewProvider, (previous, next) => unawaited(_syncDraft()));

    ref.listen<MapFocusRequest?>(mapFocusProvider, (previous, next) {
      if (next != null) _controller?.animateCamera(CameraUpdate.newLatLng(next.point));
    });
    ref.listen<MapTargetState>(mapTargetProvider, (previous, next) {
      _liveCenter = next.point == null ? null : _controller?.cameraPosition?.target;
      _syncTarget();
    });
    ref.listen<Map<MenuToggle, bool>>(menuTogglesProvider, (previous, next) => _syncTarget());
    final target = ref.watch(mapTargetProvider).point;
    final toggles = ref.watch(menuTogglesProvider);
    final menuOpen = ref.watch(crosshairMenuOpenProvider);
    final catalogSources = {
      for (final provider in ref.watch(catalogProvider).value ?? const <MapProvider>[])
        for (final source in provider.sources) source.id: source,
    };
    final layers = ref.watch(mapLayersProvider);
    // No base chosen yet: the map defaults to the server source.
    final attribution = attributionText(catalogSources[layers.baseSourceId ?? CatalogRepository.defaultBaseSourceId], [
      for (final overlay in layers.overlays)
        if (overlay.visible && catalogSources[overlay.sourceId] != null) catalogSources[overlay.sourceId]!,
    ]);
    final center = _liveCenter ?? ref.watch(mapCrosshairProvider);

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: AppConfig.mapStyleUrl,
            initialCameraPosition: initialMapCamera,
            trackCameraPosition: true,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: _onCameraIdle,
            onMapIdle: _onMapIdle,
            minMaxZoomPreference: const MinMaxZoomPreference(null, mapMaxZoom),
            // Landmarks are tapped through their own style layers; the
            // annotations in use (lines, the my-location circle) take no
            // taps. The list can't be empty, and no fill annotations exist.
            annotationConsumeTapEvents: const [AnnotationType.fill],
            onCameraMove: _onCameraMove,
            // MapLibre's own (i) can't be switched off and opens empty (it
            // lists only attributions written as links): pushed off screen,
            // AttributionButton replaces it.
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            attributionButtonMargins: const Point(-200, -200),
          ),
          if (_mapBusy && toggles[MenuToggle.mapsLoadingIndicators]!)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: LinearProgressIndicator(key: Key('map_loading_bar'), minHeight: 2),
              ),
            ),
          if (_crosshairPosition != null)
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              // No AppBar above the map anymore, so the HUD sits directly
              // under the status bar/notch -- SafeArea keeps it clear of
              // those system icons instead of overlapping them.
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder<LatLng?>(
                      valueListenable: _panelCenter,
                      builder: (context, panelCenter, _) => InfoPanel(
                        center: panelCenter ?? _crosshairPosition!,
                        zoom: _cameraZoom,
                        target: target,
                        recording: ref.watch(trackRecordingControllerProvider) is TrackRecordingActive,
                        toggles: toggles,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (target != null && center != null && toggles[MenuToggle.waypointsTargetStatus]!)
            IgnorePointer(
              child: Center(
                // A fixed spot right of the crosshair: only the number
                // changes while the map moves, so there is nothing to lag.
                child: Transform.translate(
                  offset: const Offset(12, 0),
                  child: FractionalTranslation(
                    translation: const Offset(0.5, 0),
                    child: ValueListenableBuilder<CameraPosition?>(
                      valueListenable: _liveCamera,
                      builder: (context, camera, _) => TargetDistanceLabel(
                        key: const Key('target_distance_label'),
                        from: camera?.target ?? center,
                        to: target,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Required by the map providers. At the right screen edge, level
          // with the bottom nav: under extendBody the bottom padding is the
          // nav panel (60 dp) plus the system bar.
          Positioned(
            right: MediaQuery.paddingOf(context).right + 5,
            bottom: MediaQuery.paddingOf(context).bottom - (60 + AttributionButton.size) / 2,
            child: AttributionButton(text: attribution),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              left: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ортофотопланы: одно нажатие включает или выключает; во
                  // включённом виде кнопка залита цветом.
                  MapRoundButton(
                    key: const Key('orthophoto_button'),
                    active: orthophotosOn,
                    tooltip: orthophotosOn ? 'Ортофотопланы включены' : 'Ортофотопланы выключены',
                    onTap: _toggleOrthophotos,
                    child: Semantics(
                      toggled: orthophotosOn,
                      label: 'Ортофотопланы',
                      child: AppIcon(AppIcons.drone, size: 26, color: MapRoundButton.iconColorFor(orthophotosOn)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MapZoomButtons(
                    onZoomIn: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
                    onZoomOut: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
                  ),
                ],
              ),
            ),
          ),
          // Системное «Назад» во время рисования закрывает его (с точками —
          // после вопроса), а не уходит с карты. PopScope действует на
          // весь маршрут, где бы ни стоял.
          PopScope(
            canPop: !_drawing,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _drawing) cancelDrawing(context, ref.read(landmarkServicesProvider));
            },
            child: const SizedBox.shrink(),
          ),
          // Набор точек — панелью «Управление метками» внизу
          // над нижним меню (его высота — нижний отступ).
          if (_drawing && _editMode.state.target!.type == LandmarkType.set)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom,
              child: SetPanel(
                pointCount: _editMode.pointCount,
                onAddPoint: _addDrawingPoint,
                onSearch: () => showSetPointsSheet(context, ref),
                onFinish: () => _editMode.pointCount == 0
                    ? _editMode.close()
                    : finishDrawing(context, ref.read(landmarkServicesProvider)),
              ),
            )
          else if (_drawing)
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              // Под панелью X/Y: координаты точки в прицеле видны.
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 84),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: DrawingBar(
                        type: _editMode.state.target!.type,
                        pointCount: _editMode.pointCount,
                        canUndo: _editMode.canUndo,
                        canRedo: _editMode.canRedo,
                        canFinish: _editMode.canFinish,
                        onAddPoint: _addDrawingPoint,
                        onUndo: _editMode.undo,
                        onRedo: _editMode.redo,
                        onFinish: () => finishDrawing(context, ref.read(landmarkServicesProvider)),
                        onCancel: () => cancelDrawing(context, ref.read(landmarkServicesProvider)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (menuOpen && !_drawing) ...[
            Positioned.fill(
              child: GestureDetector(
                key: const Key('crosshair_menu_barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(crosshairMenuOpenProvider.notifier).close(),
              ),
            ),
            // The card's bottom (its triangle tip) sits just above the
            // crosshair: half the screen minus the crosshair's radius.
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 8,
              bottom: MediaQuery.sizeOf(context).height / 2 + 16 + 2,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CrosshairMenu(
                  hasTarget: target != null,
                  onSetTarget: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    final center = _controller?.cameraPosition?.target ?? ref.read(mapCrosshairProvider);
                    if (center == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
                      return;
                    }
                    ref.read(mapTargetProvider.notifier).setAt(center);
                  },
                  // The target stays: the waypoint is just made at it.
                  onTargetWaypoint: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    createWaypointAtCrosshair(context, ref, iconScanner: _iconLibraryScanner, at: target);
                  },
                  onRemoveTarget: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    ref.read(mapTargetProvider.notifier).clear();
                  },
                  onInfo: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    final center = _controller?.cameraPosition?.target ?? ref.read(mapCrosshairProvider);
                    if (center == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
                      return;
                    }
                    showPointInfoSheet(
                      context,
                      point: center,
                      sk42: ref.read(menuTogglesProvider)[MenuToggle.settingsSk42Grid]!,
                    );
                  },
                  onNewWaypoint: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    openNewMarker(context, ref, iconScanner: _iconLibraryScanner);
                  },
                ),
              ),
            ),
          ],
          Center(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onCrosshairPointerDown,
              onPointerUp: _onCrosshairPointerUp,
              onPointerCancel: _onCrosshairPointerCancel,
              // Nothing inside claims the hit, so the touch also goes on to
              // the map underneath.
              child: IgnorePointer(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  // A white dot 10 dp across (as big as a landmark dot), its
                  // 1 dp dark border included.
                  child: Center(
                    child: Container(
                      key: const Key('map_crosshair'),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
