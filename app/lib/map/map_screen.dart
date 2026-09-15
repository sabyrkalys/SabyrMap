import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import '../icons/icon_image_cache.dart';
import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import 'geo_utils.dart';
import '../tracks/track_models.dart';
import '../tracks/track_name_form_sheet.dart';
import '../tracks/track_recording_controller.dart';
import '../tracks/tracks_controller.dart';
import '../tracks/tracks_list_screen.dart';
import '../waypoints/waypoint_actions.dart';
import '../waypoints/waypoint_form_sheet.dart';
import '../waypoints/waypoint_models.dart';
import '../waypoints/waypoint_types.dart';
import '../waypoints/waypoints_controller.dart';

/// Pure mapping from a waypoint (plus the current user id, to distinguish
/// own vs. shared waypoints) to the [CircleOptions] used to render it.
/// Extracted as a top-level function so it can be unit-tested without a
/// real [MapLibreMapController]/platform view.
CircleOptions circleOptionsForWaypoint(Waypoint waypoint, String currentUserId) {
  final isOwn = waypoint.ownerId == currentUserId;
  return CircleOptions(
    geometry: LatLng(waypoint.lat, waypoint.lng),
    circleRadius: 8,
    circleColor: waypoint.color ?? waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: isOwn ? '#FFFFFF' : '#000000',
    circleStrokeWidth: isOwn ? 1 : 2,
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

  // Crosshair coordinate readout: refreshed whenever the camera settles
  // (not on every drag frame, to avoid rebuilding the HUD on each pixel of
  // a pan gesture).
  LatLng? _crosshairPosition;

  bool _tracksVisible = false;
  // Tracks whether loadTracks() has run this session. Using this instead of
  // `tracksControllerProvider`'s emptiness avoids skipping the initial load
  // after the user has recorded-and-saved a track (which appends directly
  // into that state via TracksController.saveTrack, making it non-empty
  // even though the server's other previously-saved tracks were never
  // fetched).
  bool _tracksLoaded = false;

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
    _loadMyLocation();
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
    if (_hasCenteredCamera) return;
    final controller = _controller;
    final location = _myLocation;
    if (controller == null || location == null) return;
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
  }

  void _onCameraIdle() {
    final target = _controller?.cameraPosition?.target;
    if (target == null) return;
    setState(() => _crosshairPosition = target);
  }

  void _onStyleLoaded() {
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
    _maybeCenterCamera();
    _requestSync();
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
    final currentUserId = _currentUserId();

    // Waypoints with a locally-assigned icon are rendered by _syncSymbols
    // instead, so they're excluded here. Because the exclusion happens before
    // currentIds is computed, a waypoint that just gained an icon falls into
    // the removal branch below (dropping its now-obsolete circle) and gets
    // added as a Symbol on the same pass -- and vice versa when an icon is
    // cleared -- so it is never rendered as both at once.
    final circleModeWaypoints =
        waypoints.where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.circle).toList();
    final currentIds = circleModeWaypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
        _appliedCircleKeys.remove(id);
      }
    }

    for (final waypoint in circleModeWaypoints) {
      // circleOptionsForWaypoint is a pure function of (waypoint.type,
      // isOwn, waypoint.color) — nothing else it reads ever varies for a
      // given waypoint id — so this key cheaply captures "would the
      // rendered options change".
      final isOwn = waypoint.ownerId == currentUserId;
      final key = '${waypoint.type}|$isOwn|${waypoint.color ?? ''}';
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        final options = circleOptionsForWaypoint(waypoint, currentUserId);
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
        _appliedCircleKeys[waypoint.id] = key;
      } else if (_appliedCircleKeys[waypoint.id] != key) {
        await controller.updateCircle(existing, circleOptionsForWaypoint(waypoint, currentUserId));
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

    final symbolModeWaypoints =
        waypoints.where((w) => renderModeForWaypoint(iconAssignments[w.id]) == WaypointRenderMode.symbol).toList();
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

    final tracks = _tracksVisible ? ref.read(tracksControllerProvider) : const <Track>[];
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

  String _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.user.id : '';
  }

  Future<void> _createWaypointAtCrosshair() async {
    final controller = _controller;
    final cameraPosition = controller?.cameraPosition;
    if (controller == null || cameraPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Карта ещё не готова')),
      );
      return;
    }
    final coordinates = cameraPosition.target;
    final result = await showWaypointFormSheet(context, iconScanner: _iconLibraryScanner);
    if (result == null || !mounted) return;
    try {
      final created = await ref.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: _currentUserId(),
            name: result.name,
            type: result.type,
            note: result.note,
            color: result.color,
            lat: coordinates.latitude,
            lng: coordinates.longitude,
          );
      try {
        await ref.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(created.id, result.iconFileName);
      } catch (_) {
        // The waypoint itself was created; a local icon-bookkeeping failure
        // is a soft failure and shouldn't be reported as a failed creation.
        // Same reasoning as editWaypoint/deleteWaypoint in
        // waypoint_actions.dart.
      }
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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

  String _defaultTrackName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Трек ${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
  }

  Future<void> _onRecordToggle(TrackRecordingState recordingState) async {
    if (recordingState is TrackRecordingActive) {
      final stopResult = ref.read(trackRecordingControllerProvider.notifier).stop();
      if (stopResult == null || stopResult.points.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Трек слишком короткий, чтобы сохранить')),
          );
        }
        return;
      }
      final result = await showTrackNameFormSheet(context, initialName: _defaultTrackName());
      if (result == null || !mounted) return;
      try {
        await ref.read(tracksControllerProvider.notifier).saveTrack(
              name: result.name,
              points: stopResult.points,
              startedAt: stopResult.startedAt,
              finishedAt: stopResult.finishedAt,
            );
      } on TrackException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } else {
      await ref.read(trackRecordingControllerProvider.notifier).start();
      final newState = ref.read(trackRecordingControllerProvider);
      if (newState is TrackRecordingIdle && newState.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newState.errorMessage!)));
      }
    }
  }

  Future<void> _onTracksVisibilityChanged(bool visible) async {
    setState(() => _tracksVisible = visible);
    if (visible && !_tracksLoaded) {
      await ref.read(tracksControllerProvider.notifier).loadTracks();
      _tracksLoaded = true;
    }
    _requestSync();
  }

  void _onLayersButtonPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Показывать треки'),
              Switch(
                key: const Key('tracks_visibility_switch'),
                value: _tracksVisible,
                onChanged: (value) {
                  setSheetState(() {});
                  _onTracksVisibilityChanged(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
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

    final recordingState = ref.watch(trackRecordingControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
          IconButton(
            key: const Key('track_record_toggle'),
            icon: Icon(recordingState is TrackRecordingActive ? Icons.stop_circle : Icons.fiber_manual_record),
            onPressed: () => _onRecordToggle(recordingState),
          ),
          IconButton(
            key: const Key('layers_button'),
            icon: const Icon(Icons.layers),
            onPressed: _onLayersButtonPressed,
          ),
          IconButton(
            key: const Key('tracks_list_button'),
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TracksListScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: AppConfig.mapStyleUrl,
            initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 1),
            trackCameraPosition: true,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: _onCameraIdle,
          ),
          if (_crosshairPosition != null)
            Positioned(top: 12, left: 12, child: _CoordinateHud(target: _crosshairPosition!, myLocation: _myLocation)),
          IgnorePointer(
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_waypoint_button'),
        onPressed: _createWaypointAtCrosshair,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Метка здесь'),
      ),
    );
  }
}

/// Small HUD card showing the crosshair's coordinates and, when the user's
/// own position is known, the distance and bearing from it to the crosshair.
class _CoordinateHud extends StatelessWidget {
  const _CoordinateHud({required this.target, required this.myLocation});

  final LatLng target;
  final TrackPoint? myLocation;

  @override
  Widget build(BuildContext context) {
    final location = myLocation;
    final distance = location == null
        ? null
        : distanceMeters(location.lat, location.lng, target.latitude, target.longitude);
    final bearing =
        location == null ? null : bearingDegrees(location.lat, location.lng, target.latitude, target.longitude);

    return Card(
      key: const Key('coordinate_hud'),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (distance != null && bearing != null)
              Text('${distance.round()} м · ${bearing.round()}°'),
          ],
        ),
      ),
    );
  }
}
