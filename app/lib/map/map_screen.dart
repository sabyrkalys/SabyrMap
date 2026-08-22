import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import '../tracks/track_models.dart';
import '../tracks/track_name_form_sheet.dart';
import '../tracks/track_recording_controller.dart';
import '../tracks/tracks_controller.dart';
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
    circleColor: waypointTypeColors[waypoint.type] ?? waypointTypeColors[defaultWaypointType]!,
    circleStrokeColor: isOwn ? '#FFFFFF' : '#000000',
    circleStrokeWidth: isOwn ? 1 : 2,
  );
}

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
  bool _tracksVisible = false;

  // Serializes _syncCircles/_syncLines runs together: at most one combined
  // sync runs at a time, and any state change that arrives while a run is
  // in flight is coalesced into a single trailing re-run (rather than
  // racing concurrently against the in-flight one, which could orphan or
  // duplicate circles/lines).
  bool _isSyncing = false;
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(waypointsControllerProvider.notifier).loadWaypoints();
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onStyleLoaded() {
    // Every style (re)load disposes and re-creates maplibre_gl's annotation
    // managers, which wipes their internal id tracking. Drop our own
    // tracking too so the next sync re-adds every circle/line from scratch
    // instead of trying to update ids the new manager doesn't know about.
    _circlesByWaypointId.clear();
    _linesByTrackId.clear();
    _requestSync();
  }

  /// Entry point for requesting a combined circle+line sync. Coalesces
  /// concurrent requests so only one sync run is ever in flight; both
  /// [_syncCircles] and [_syncLines] read fresh state via `ref.read` when
  /// they actually run, rather than being handed a snapshot up front.
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
      await _syncCircles(ref.read(waypointsControllerProvider));
      await _syncLines();
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

  Future<void> _syncCircles(List<Waypoint> waypoints) async {
    final controller = _controller;
    // The circle manager is only initialized after onStyleLoadedCallback
    // fires; addCircle/updateCircle/removeCircle throw before then. A sync
    // can otherwise be requested (via the waypoints ref.listen callback,
    // once loadWaypoints() resolves) in the window after onMapCreated but
    // before the style has finished loading, so guard on both.
    if (controller == null || controller.circleManager == null) return;
    final currentUserId = _currentUserId();

    final currentIds = waypoints.map((w) => w.id).toSet();
    for (final id in _circlesByWaypointId.keys.toList()) {
      if (!currentIds.contains(id)) {
        await controller.removeCircle(_circlesByWaypointId.remove(id)!);
      }
    }

    for (final waypoint in waypoints) {
      final options = circleOptionsForWaypoint(waypoint, currentUserId);
      final existing = _circlesByWaypointId[waypoint.id];
      if (existing == null) {
        _circlesByWaypointId[waypoint.id] = await controller.addCircle(options, {'waypointId': waypoint.id});
      } else {
        await controller.updateCircle(existing, options);
      }
    }
  }

  Future<void> _syncLines() async {
    final controller = _controller;
    // Same readiness guard as _syncCircles, for the line manager.
    if (controller == null || controller.lineManager == null) return;

    final tracks = _tracksVisible ? ref.read(tracksControllerProvider) : const <Track>[];
    final currentIds = tracks.map((t) => t.id).toSet();
    for (final id in _linesByTrackId.keys.toList()) {
      if (id == _recordingLineKey) continue;
      if (!currentIds.contains(id)) {
        await controller.removeLine(_linesByTrackId.remove(id)!);
      }
    }

    for (final track in tracks) {
      final options = LineOptions(
        geometry: [for (final p in track.points) LatLng(p.lat, p.lng)],
        lineColor: '#1976D2',
        lineWidth: 3,
      );
      final existing = _linesByTrackId[track.id];
      if (existing == null) {
        _linesByTrackId[track.id] = await controller.addLine(options);
      } else {
        await controller.updateLine(existing, options);
      }
    }

    final recordingState = ref.read(trackRecordingControllerProvider);
    if (recordingState is TrackRecordingActive && recordingState.points.length >= 2) {
      final options = LineOptions(
        geometry: [for (final p in recordingState.points) LatLng(p.lat, p.lng)],
        lineColor: '#E53935',
        lineWidth: 4,
      );
      final existing = _linesByTrackId[_recordingLineKey];
      if (existing == null) {
        _linesByTrackId[_recordingLineKey] = await controller.addLine(options);
      } else {
        await controller.updateLine(existing, options);
      }
    } else {
      final existing = _linesByTrackId.remove(_recordingLineKey);
      if (existing != null) {
        await controller.removeLine(existing);
      }
    }
  }

  String _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.user.id : '';
  }

  Future<void> _onMapLongClick(Point<double> point, LatLng coordinates) async {
    final result = await showWaypointFormSheet(context);
    if (result == null || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: _currentUserId(),
            name: result.name,
            type: result.type,
            note: result.note,
            lat: coordinates.latitude,
            lng: coordinates.longitude,
          );
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
    _showWaypointDetails(waypoints[index]);
  }

  Future<void> _showWaypointDetails(Waypoint waypoint) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(waypoint.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(waypointTypeLabels[waypoint.type] ?? waypoint.type),
            if (waypoint.note != null && waypoint.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(waypoint.note!),
            ],
            if (waypoint.canEdit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    key: const Key('waypoint_edit_button'),
                    onPressed: () => Navigator.of(context).pop('edit'),
                    child: const Text('Изменить'),
                  ),
                  TextButton(
                    key: const Key('waypoint_delete_button'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editWaypoint(waypoint);
    } else if (action == 'delete') {
      await _deleteWaypoint(waypoint);
    }
  }

  Future<void> _editWaypoint(Waypoint waypoint) async {
    final result = await showWaypointFormSheet(context, existing: waypoint);
    if (result == null || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).updateWaypoint(
            waypoint.id,
            name: result.name,
            type: result.type,
            note: result.note,
          );
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteWaypoint(Waypoint waypoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить метку?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(waypointsControllerProvider.notifier).deleteWaypoint(waypoint.id);
    } on WaypointException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _defaultTrackName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Трек ${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
  }

  Future<void> _onRecordToggle(TrackRecordingState recordingState) async {
    if (recordingState is TrackRecordingActive) {
      final points = ref.read(trackRecordingControllerProvider.notifier).stop();
      if (points.length < 2) {
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
        await ref.read(tracksControllerProvider.notifier).saveTrack(name: result.name, points: points);
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
    if (visible && ref.read(tracksControllerProvider).isEmpty) {
      await ref.read(tracksControllerProvider.notifier).loadTracks();
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
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: MapLibreMap(
        styleString: AppConfig.mapStyleUrl,
        initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 1),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        onMapLongClick: _onMapLongClick,
      ),
    );
  }
}
