import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
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

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  final Map<String, Circle> _circlesByWaypointId = {};

  // Serializes _syncCircles runs: at most one runs at a time, and a state
  // change that arrives while a run is in flight is coalesced into a single
  // trailing re-run (rather than racing concurrently against the in-flight
  // one, which could orphan or duplicate circles).
  bool _isSyncing = false;
  List<Waypoint>? _pendingWaypoints;

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
    // tracking too so the next sync re-adds every circle from scratch
    // instead of trying to update ids the new manager doesn't know about.
    _circlesByWaypointId.clear();
    _requestSync(ref.read(waypointsControllerProvider));
  }

  /// Entry point for requesting a circle sync. Coalesces concurrent
  /// requests so only one [_syncCircles] run is ever in flight.
  void _requestSync(List<Waypoint> waypoints) {
    if (_isSyncing) {
      _pendingWaypoints = waypoints;
      return;
    }
    _runSync(waypoints);
  }

  Future<void> _runSync(List<Waypoint> waypoints) async {
    _isSyncing = true;
    try {
      await _syncCircles(waypoints);
    } catch (_) {
      // Swallow sync failures (e.g. the circle manager wasn't ready yet, or
      // a style reload raced with an in-flight call): the next waypoints
      // state change or style-loaded event will retry from a clean slate.
    } finally {
      _isSyncing = false;
    }
    final pending = _pendingWaypoints;
    if (pending != null) {
      _pendingWaypoints = null;
      _requestSync(pending);
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

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Waypoint>>(waypointsControllerProvider, (previous, next) {
      _requestSync(next);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
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
