import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import '../icons/icon_image_cache.dart';
import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import 'attribution_bar.dart';
import 'models/map_models.dart';
import 'catalog/catalog_repository.dart';
import 'crosshair_menu.dart';
import 'info_panel.dart';
import 'map_camera_store.dart';
import 'map_crosshair.dart';
import 'map_overlays.dart';
import 'map_scale.dart';
import 'map_target.dart';
import 'point_info_sheet.dart';
import 'services/google_tiles_service.dart';
import 'services/layer_manager.dart';
import 'services/maplibre_layer_host.dart';
import 'services/yandex_tiles_service.dart';
import 'state/map_layers_controller.dart';
import 'state/map_viewport.dart';
import '../menu/menu_toggles.dart';
import '../tracks/track_models.dart';
import '../tracks/track_recording_controller.dart';
import '../tracks/tracks_controller.dart';
import '../tracks/tracks_visibility_controller.dart';
import '../waypoints/waypoint_actions.dart';
import '../waypoints/waypoint_create_action.dart';
import '../waypoints/waypoint_models.dart';
import '../waypoints/waypoint_types.dart';
import '../waypoints/waypoints_controller.dart';

/// Pure mapping from a waypoint to the [CircleOptions] used to render it.
/// Extracted as a top-level function so it can be unit-tested without a
/// real [MapLibreMapController]/platform view.
CircleOptions circleOptionsForWaypoint(Waypoint waypoint) {
  return CircleOptions(
    geometry: LatLng(waypoint.lat, waypoint.lng),
    circleRadius: 8,
    circleColor: waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: '#FFFFFF',
    circleStrokeWidth: 1,
  );
}

enum WaypointRenderMode { circle, symbol }

/// Pure routing decision: a waypoint with a locally-assigned icon renders as
/// an image Symbol; everything else keeps the existing colored Circle.
/// Extracted as a top-level function for the same reason
/// [circleOptionsForWaypoint] is -- unit-testable without a platform view.
WaypointRenderMode renderModeForWaypoint(String? assignedIconFileName) =>
    assignedIconFileName == null ? WaypointRenderMode.circle : WaypointRenderMode.symbol;

const String _recordingLineKey = '__recording__';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  final Map<String, Circle> _circlesByWaypointId = {};
  final Map<String, Line> _linesByTrackId = {};
  // Caches a cheap "did this actually change" key per circle/line id so
  // _syncCircles/_syncLines only issue an updateCircle/updateLine platform
  // call when the rendered options for that particular id would differ from
  // what's already applied, instead of re-pushing every waypoint/track on
  // every sync run (which otherwise happens on every single recorded GPS
  // point, since the recording stream routes through the same sync gate).
  final Map<String, String> _appliedCircleKeys = {};
  final Map<String, String> _appliedLineKeys = {};

  // The Symbol counterpart of the circle tracking above, for waypoints that
  // have a locally-assigned icon file (see renderModeForWaypoint). Same
  // invariants: one entry per waypoint id, plus an applied-key cache so a
  // sync only issues an updateSymbol platform call when the rendered image
  // for that id would actually differ.
  final Map<String, Symbol> _symbolsByWaypointId = {};
  final Map<String, String> _appliedSymbolKeys = {};
  late final IconImageCache _iconImageCache = IconImageCache(
    addImage: (name, bytes) async {
      final controller = _controller;
      if (controller == null) return;
      await controller.addImage(name, bytes);
    },
  );
  final IconLibraryScanner _iconLibraryScanner = IconLibraryScanner();
  // Cached so _syncSymbols (which can run many times per second while a
  // track is recording, same as _syncCircles) doesn't rescan the device
  // folder on every tick. A file name that isn't in the map triggers exactly
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

  // «Задать цель» line: one annotation, refreshed on every camera change
  // while a target is set. Serialized like _requestSync so rapid camera
  // ticks never run overlapping add/update calls.
  Line? _targetLine;
  // Dot at the target start, the size of the crosshair's centre dot; the
  // crosshair itself marks the other end of the line.
  Circle? _targetDot;
  bool _targetLineBusy = false;
  bool _targetLinePending = false;
  // Live camera centre, tracked only while a target is set so the distance
  // label follows a drag without rebuilding on every frame otherwise.
  LatLng? _liveCenter;

  // Serializes _syncCircles/_syncLines runs together: at most one combined
  // sync runs at a time, and any state change that arrives while a run is
  // in flight is coalesced into a single trailing re-run (rather than
  // racing concurrently against the in-flight one, which could orphan or
  // duplicate circles/lines).
  bool _isSyncing = false;
  bool _syncPending = false;

  // Captured in initState rather than read directly inside dispose(): by the
  // time State.dispose() runs, the widget's element is already deactivated
  // and using `ref` throws ("Using ref when a widget is about to or has
  // been unmounted is unsafe"). The notifier instance itself is stable for
  // the lifetime of the (root-scope, non-autoDispose) provider, so grabbing
  // it once up front and calling stop() on it later is safe.
  late final TrackRecordingController _recordingController;

  @override
  void initState() {
    super.initState();
    _recordingController = ref.read(trackRecordingControllerProvider.notifier);
    Future.microtask(() {
      if (!mounted) return;
      ref.read(waypointsControllerProvider.notifier).loadWaypoints();
    });
    // Icon assignments live entirely on the device (flutter_secure_storage),
    // so unlike loadWaypoints() this never reaches the backend. A failure to
    // read them back is a soft failure -- every waypoint simply keeps
    // rendering as a plain circle -- and is swallowed for the same reason
    // waypoint_actions.dart swallows icon-store write failures, rather than
    // surfacing as an unhandled async error.
    Future.microtask(() async {
      if (!mounted) return;
      try {
        await ref.read(waypointIconAssignmentsControllerProvider.notifier).load();
      } catch (_) {}
    });
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
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
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
    );
    final result = await ref.read(mapLayersProvider.notifier).attach(manager);
    if (!result.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.problems.join('\n'))));
    }
  }

  // Driven by MapLibreMap.onCameraMove, not a controller listener: the
  // controller also notifies its listeners after every add/update/removeLine,
  // so listening there made each line update trigger the next one forever.
  //
  // The zoom feeds the info panel's scale readout during a pinch; to avoid a
  // rebuild on every frame it is only applied once it moved by 0.1 or more.
  void _onCameraMove(CameraPosition position) {
    final zoomChanged = (position.zoom - _cameraZoom).abs() >= 0.1;
    final hasTarget = ref.read(mapTargetProvider).point != null;
    if (!zoomChanged && !hasTarget) return;
    if (mounted) {
      setState(() {
        if (zoomChanged) _cameraZoom = position.zoom;
        if (hasTarget) _liveCenter = position.target;
      });
    }
    if (hasTarget) _syncTargetLine();
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
    ref.read(crosshairMenuOpenProvider.notifier).toggle();
  }

  void _onCrosshairPointerCancel(PointerCancelEvent event) {
    _crosshairPointers.remove(event.pointer);
    if (_crosshairPointers.isEmpty) _crosshairMultiTouch = false;
  }

  static const double _targetDotRadius = 3; // 6 dp, like the crosshair's centre dot
  static const String _targetDotColorHex = '#1A1C1E';

  Future<void> _syncTargetLine() async {
    if (_targetLineBusy) {
      _targetLinePending = true;
      return;
    }
    _targetLineBusy = true;
    try {
      do {
        _targetLinePending = false;
        final controller = _controller;
        if (controller == null) return;
        final target = ref.read(mapTargetProvider).point;
        final showLine = ref.read(menuTogglesProvider)[MenuToggle.waypointsTargetLine]!;
        final center = _liveCenter ?? controller.cameraPosition?.target;
        final existing = _targetLine;
        final existingDot = _targetDot;
        if (target == null || !showLine || center == null) {
          if (existing != null) {
            _targetLine = null;
            await controller.removeLine(existing);
          }
          if (existingDot != null) {
            _targetDot = null;
            await controller.removeCircle(existingDot);
          }
        } else {
          final dot = CircleOptions(geometry: target, circleRadius: _targetDotRadius, circleColor: _targetDotColorHex);
          if (existingDot == null) {
            _targetDot = await controller.addCircle(dot);
          } else if (existingDot.options.geometry != target) {
            await controller.updateCircle(existingDot, dot);
          }
          final options = LineOptions(geometry: [center, target], lineColor: targetLineColorHex, lineWidth: 3);
          if (existing == null) {
            _targetLine = await controller.addLine(options);
          } else {
            await controller.updateLine(existing, options);
          }
        }
      } while (_targetLinePending);
    } catch (_) {
      // Same soft-failure policy as _runSync: a manager not ready yet or a
      // style reload race; the next camera tick or state change retries.
    } finally {
      _targetLineBusy = false;
    }
  }

  void _onCameraIdle() {
    final position = _controller?.cameraPosition;
    if (position == null) return;
    setState(() {
      _crosshairPosition = position.target;
      _cameraZoom = position.zoom;
    });
    ref.read(mapCrosshairProvider.notifier).set(position.target);
    if (_savedCameraLoaded && shouldPersistCamera(position, cameraRestored: _hasCenteredCamera)) {
      ref.read(mapCameraStoreProvider).save(position).catchError((_) {});
    }
  }

  Future<void> _onStyleLoaded() async {
    _layerHost?.notifyStyleLoaded();
    final controller = _controller;
    if (!_layersAttached && controller != null) {
      _layersAttached = true;
      _attachLayers(controller);
    }
    // Every style (re)load disposes and re-creates maplibre_gl's annotation
    // managers, which wipes their internal id tracking. Drop our own
    // tracking too so the next sync re-adds every circle/line from scratch
    // instead of trying to update ids the new manager doesn't know about.
    _circlesByWaypointId.clear();
    _linesByTrackId.clear();
    _appliedCircleKeys.clear();
    _appliedLineKeys.clear();
    // Symbols are managed by a manager that's re-created exactly like the
    // circle/line ones, and the images they reference are registered against
    // the style itself -- neither survives a reload, so drop both the symbol
    // tracking and the registered-image bookkeeping.
    _symbolsByWaypointId.clear();
    _appliedSymbolKeys.clear();
    _iconImageCache.clear();
    _myLocationCircle = null;
    _targetLine = null;
    _targetDot = null;
    // The symbol manager defaults to iconAllowOverlap/iconIgnorePlacement:
    // false, so symbol placement collides against every symbol on the map
    // (including the basemap style's own POI/label symbols). Without this,
    // nearby waypoint icons -- or one sitting under a basemap label -- can
    // be silently culled. The setter is idempotent, so it's safe to call on
    // every style load. Wrapped in try/catch since this callback is invoked
    // fire-and-forget by maplibre_gl (no await, no error handler upstream):
    // an unguarded throw here (e.g. a style-reload/dispose race) would both
    // surface as an unhandled async error and skip _maybeCenterCamera()/
    // _requestSync() below, silently leaving the map empty until some
    // unrelated state change happens to trigger another sync.
    try {
      await _controller?.symbolManager?.setIconAllowOverlap(true);
    } catch (_) {}
    _maybeCenterCamera();
    _requestSync();
    _syncTargetLine();
  }

  /// Entry point for requesting a combined circle+symbol+line sync. Coalesces
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
      // Read once and hand the same snapshot to both renderers, so a
      // waypoint can't be classified as circle-mode by one and symbol-mode
      // by the other within a single sync pass (which would render it twice).
      final iconAssignments = ref.read(waypointIconAssignmentsControllerProvider);
      final waypoints = ref.read(waypointsControllerProvider);
      await _syncCircles(waypoints, iconAssignments);
      await _syncSymbols(waypoints, iconAssignments);
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

  Future<void> _syncCircles(List<Waypoint> waypoints, Map<String, String> iconAssignments) async {
    final controller = _controller;
    // The circle manager is only initialized after onStyleLoadedCallback
    // fires; addCircle/updateCircle/removeCircle throw before then. A sync
    // can otherwise be requested (via the waypoints ref.listen callback,
    // once loadWaypoints() resolves) in the window after onMapCreated but
    // before the style has finished loading, so guard on both.
    if (controller == null || controller.circleManager == null) return;
    // A style reload disposes and re-creates the circle manager, but
    // onStyleLoadedCallback (which clears _circlesByWaypointId) only fires
    // after the new manager already exists. If a sync landed in that gap,
    // our tracking map could still hold Circle objects belonging to the
    // disposed manager, which controller.updateCircle would then silently
    // (in release builds) insert into the new manager instead of throwing.
    // Reconcile against the manager's live set first so a stale entry is
    // dropped (and re-added fresh) rather than "updated" into limbo.
    final liveCircleIds = controller.circles.map((c) => c.id).toSet();
    _circlesByWaypointId.removeWhere((id, circle) {
      final stale = !liveCircleIds.contains(circle.id);
      if (stale) _appliedCircleKeys.remove(id);
      return stale;
    });

    // Waypoints with a locally-assigned icon are rendered by _syncSymbols
    // instead, so they're excluded here. Because the exclusion happens before
    // currentIds is computed, a waypoint that just gained an icon falls into
    // the removal branch below (dropping its now-obsolete circle) and gets
    // added as a Symbol on the same pass -- and vice versa when an icon is
    // cleared -- so it is never rendered as both at once.
    final circleModeWaypoints = waypoints
        .where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.circle)
        .toList();
    final currentIds = circleModeWaypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
        _appliedCircleKeys.remove(id);
      }
    }

    for (final waypoint in circleModeWaypoints) {
      // circleOptionsForWaypoint is a pure function of (waypoint.type,
      // waypoint.color) — nothing else it reads ever varies for a given
      // waypoint id — so this key cheaply captures "would the rendered
      // options change".
      final key = '${waypoint.type}|${waypoint.color ?? ''}';
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        final options = circleOptionsForWaypoint(waypoint);
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
        _appliedCircleKeys[waypoint.id] = key;
      } else if (_appliedCircleKeys[waypoint.id] != key) {
        await controller.updateCircle(existing, circleOptionsForWaypoint(waypoint));
        _appliedCircleKeys[waypoint.id] = key;
      }
    }
  }

  /// The Symbol counterpart of [_syncCircles], for waypoints that have a
  /// locally-assigned icon file. Deliberately mirrors _syncCircles step for
  /// step (readiness guard, stale-manager reconciliation, remove-then-add,
  /// applied-key caching) -- see that method's comments for why each step is
  /// there; the only extra work here is resolving the icon file and
  /// registering its rendered bitmap as a named style image.
  Future<void> _syncSymbols(List<Waypoint> waypoints, Map<String, String> iconAssignments) async {
    final controller = _controller;
    if (controller == null || controller.symbolManager == null) return;

    final liveSymbolIds = controller.symbols.map((s) => s.id).toSet();
    _symbolsByWaypointId.removeWhere((id, symbol) {
      final stale = !liveSymbolIds.contains(symbol.id);
      if (stale) _appliedSymbolKeys.remove(id);
      return stale;
    });

    final symbolModeWaypoints = waypoints
        .where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.symbol)
        .toList();
    final currentIds = symbolModeWaypoints.map((w) => w.id).toSet();
    for (final id in _symbolsByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeSymbol(_symbolsByWaypointId.remove(id)!);
        _appliedSymbolKeys.remove(id);
      }
    }

    for (final waypoint in symbolModeWaypoints) {
      // Non-null by construction: renderModeForWaypoint only returns symbol
      // for a waypoint that has an assignment.
      final fileName = iconAssignments[waypoint.id]!;
      // The rendered bitmap is a pure function of (icon file, effective
      // color) -- raster icons ignore the color entirely (symbolImageName
      // encodes that), so this key is a safe "would the image change" proxy.
      final colorHex = waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!;
      final key = '$fileName|$colorHex';
      final existing = _symbolsByWaypointId[waypoint.id];
      if (existing != null && _appliedSymbolKeys[waypoint.id] == key) continue;

      final iconFile = await _resolveIconFile(fileName);
      // The file was deleted from the device folder: leave whatever is
      // currently rendered in place rather than crashing or silently blanking
      // the marker. The next sync after the user clears/reassigns the icon
      // picks the waypoint up again.
      if (iconFile == null) continue;
      final imageName = await _iconImageCache.resolve(iconFile, colorHex);
      final options = SymbolOptions(
        geometry: LatLng(waypoint.lat, waypoint.lng),
        iconImage: imageName,
        // Every rendered icon bitmap is normalized to the same fixed canvas
        // (kIconCanvasSize), so a single constant scale is correct for all of
        // them -- no per-waypoint sizing needed.
        iconSize: 1,
      );
      if (existing == null) {
        _symbolsByWaypointId[waypoint.id] = await controller.addSymbol(options, {'waypointId': waypoint.id});
      } else {
        await controller.updateSymbol(existing, options);
      }
      _appliedSymbolKeys[waypoint.id] = key;
    }
  }

  /// Resolves an assigned icon file name to the [IconFile] describing it,
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

    final tracksVisible = ref.read(tracksVisibilityControllerProvider);
    final tracks = tracksVisible ? ref.read(tracksControllerProvider) : const <Track>[];
    final currentIds = tracks.map((t) => t.id).toSet();
    for (final id in _linesByTrackId.keys.toList()) {
      if (id == _recordingLineKey) continue;
      if (!currentIds.contains(id)) {
        await controller.removeLine(_linesByTrackId.remove(id)!);
        _appliedLineKeys.remove(id);
      }
    }

    for (final track in tracks) {
      // Cheap proxy for "did the geometry change": point count plus the
      // last point's coordinates. Exact correctness matters less than
      // avoiding the worst case of re-pushing every unrelated track's full
      // geometry on every recording-stream tick.
      final key = _geometryKey(track.points.map((p) => (p.lat, p.lng)).toList());
      final existing = _linesByTrackId[track.id];
      if (existing == null) {
        final options = LineOptions(
          geometry: [for (final p in track.points) LatLng(p.lat, p.lng)],
          lineColor: '#1976D2',
          lineWidth: 3,
        );
        _linesByTrackId[track.id] = await controller.addLine(options);
        _appliedLineKeys[track.id] = key;
      } else if (_appliedLineKeys[track.id] != key) {
        final options = LineOptions(
          geometry: [for (final p in track.points) LatLng(p.lat, p.lng)],
          lineColor: '#1976D2',
          lineWidth: 3,
        );
        await controller.updateLine(existing, options);
        _appliedLineKeys[track.id] = key;
      }
    }

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

  void _onCircleTapped(Circle circle) {
    final waypointId = circle.data?['waypointId'] as String?;
    if (waypointId == null) return;
    final waypoints = ref.read(waypointsControllerProvider);
    final index = waypoints.indexWhere((w) => w.id == waypointId);
    if (index == -1) return;
    showWaypointDetails(context, ref, waypoints[index]);
  }

  /// Same routing as [_onCircleTapped], for waypoints rendered as image
  /// Symbols -- tapping either kind of marker opens the same details sheet.
  void _onSymbolTapped(Symbol symbol) {
    final waypointId = symbol.data?['waypointId'] as String?;
    if (waypointId == null) return;
    final waypoints = ref.read(waypointsControllerProvider);
    final index = waypoints.indexWhere((w) => w.id == waypointId);
    if (index == -1) return;
    showWaypointDetails(context, ref, waypoints[index]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Waypoint>>(waypointsControllerProvider, (previous, next) {
      _requestSync();
    });
    ref.listen<List<Track>>(tracksControllerProvider, (previous, next) {
      _requestSync();
    });
    ref.listen<TrackRecordingState>(trackRecordingControllerProvider, (previous, next) {
      _requestSync();
    });
    // An icon assignment changing flips a waypoint between the circle and
    // symbol renderer, which only happens on a sync pass -- so it has to
    // request one just like a waypoint list change does.
    ref.listen<Map<String, String>>(waypointIconAssignmentsControllerProvider, (previous, next) {
      _requestSync();
    });
    // The visibility toggle lives on the Метки tab now; a change there
    // still has to reach this screen's own sync loop.
    ref.listen<bool>(tracksVisibilityControllerProvider, (previous, next) {
      _requestSync();
    });

    ref.listen<MapTargetState>(mapTargetProvider, (previous, next) {
      _liveCenter = next.point == null ? null : _controller?.cameraPosition?.target;
      _syncTargetLine();
    });
    ref.listen<Map<MenuToggle, bool>>(menuTogglesProvider, (previous, next) => _syncTargetLine());
    final target = ref.watch(mapTargetProvider).point;
    final toggles = ref.watch(menuTogglesProvider);
    final menuOpen = ref.watch(crosshairMenuOpenProvider);
    final center = _liveCenter ?? ref.watch(mapCrosshairProvider);
    final catalogSources = {
      for (final provider in ref.watch(catalogProvider).value ?? const <MapProvider>[])
        for (final source in provider.sources) source.id: source,
    };
    final layers = ref.watch(mapLayersProvider);
    // No base chosen yet: the map shows its initial style (OpenFreeMap Liberty).
    final attribution = attributionText(catalogSources[layers.baseSourceId ?? 'ofm-liberty'], [
      for (final overlay in layers.overlays)
        if (overlay.visible && catalogSources[overlay.sourceId] != null) catalogSources[overlay.sourceId]!,
    ]);

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
            minMaxZoomPreference: const MinMaxZoomPreference(null, mapMaxZoom),
            // Lines never take taps (nothing in the app handles them).
            annotationConsumeTapEvents: const [AnnotationType.symbol, AnnotationType.circle, AnnotationType.fill],
            onCameraMove: _onCameraMove,
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
                    child: InfoPanel(
                      center: infoPanelCenter(target: target, liveCenter: _liveCenter, settled: _crosshairPosition!),
                      zoom: _cameraZoom,
                      target: target,
                      recording: ref.watch(trackRecordingControllerProvider) is TrackRecordingActive,
                      toggles: toggles,
                    ),
                  ),
                ),
              ),
            ),
          if (target != null && center != null && toggles[MenuToggle.waypointsTargetStatus]!)
            IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -34),
                  child: TargetDistanceLabel(key: const Key('target_distance_label'), from: center, to: target),
                ),
              ),
            ),
          // Required by the map providers; left of the zoom buttons, just
          // above the bottom nav.
          Positioned(
            left: 8,
            right: 88,
            bottom: MediaQuery.paddingOf(context).bottom + 4,
            child: IgnorePointer(
              child: Align(alignment: Alignment.bottomLeft, child: AttributionBar(text: attribution)),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              left: false,
              child: MapZoomButtons(
                onZoomIn: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
                onZoomOut: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
              ),
            ),
          ),
          if (menuOpen) ...[
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
                    createWaypointAtCrosshair(context, ref, iconScanner: _iconLibraryScanner);
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
                  child: Center(
                    child: Container(
                      key: const Key('map_crosshair'),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
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
