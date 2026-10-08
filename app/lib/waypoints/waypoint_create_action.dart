import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import '../map/map_crosshair.dart';
import 'waypoint_dialog/waypoint_data.dart';
import 'waypoint_dialog/waypoint_dialog.dart';
import 'waypoint_models.dart';
import 'waypoints_controller.dart';

/// Opens the «Путевая точка» dialog and creates the waypoint at the map's
/// crosshair, or at [at] (the «Задать цель» target). With «Указать точку на
/// карте» it is created where the map is tapped next ([waypointPlacementProvider]).
/// Shared by the crosshair menu, the «Новая метка» sheet and the МЕТКИ panel.
///
/// The panel can be closed while the request is in flight, which unmounts
/// [context] and disposes [ref]; the container and messenger are captured
/// up front so the result is still applied and reported.
Future<void> createWaypointAtCrosshair(
  BuildContext context,
  WidgetRef ref, {
  IconLibraryScanner? iconScanner,
  LatLng? at,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final coordinates = at ?? ref.read(mapCrosshairProvider);
  if (coordinates == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final data = await showWaypointDialog(
    context,
    iconScanner: iconScanner,
    pointLabel: at == null ? 'Координаты центра экрана' : 'Координаты цели',
  );
  if (data == null) return;
  if (data.coords == WaypointCoords.customPoint) {
    container.read(waypointPlacementProvider.notifier).start(data);
    return;
  }
  await saveWaypoint(container, messenger, data, coordinates);
}

/// Creates [data] at [at]. An empty name becomes the next «Путевая точка N».
Future<void> saveWaypoint(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  WaypointData data,
  LatLng at,
) async {
  final name = data.name.trim().isNotEmpty
      ? data.name.trim()
      : nextWaypointName(container.read(waypointsControllerProvider).map((w) => w.name));
  try {
    final created = await container.read(waypointsControllerProvider.notifier).createWaypoint(
          name: name,
          type: data.type,
          note: data.note,
          color: data.colorHex,
          lat: at.latitude,
          lng: at.longitude,
        );
    try {
      await container.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(created.id, data.iconId);
    } catch (_) {
      // The waypoint itself was created; a local icon-bookkeeping failure
      // is a soft failure and shouldn't be reported as a failed creation.
      // Same reasoning as editWaypoint/deleteWaypoint in waypoint_actions.dart.
    }
  } on WaypointException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// A waypoint from the dialog that waits for its point: «Указать точку на
/// карте». The map screen creates it at the next tap on the map.
class WaypointPlacement extends Notifier<WaypointData?> {
  @override
  WaypointData? build() => null;

  void start(WaypointData data) => state = data;

  void cancel() => state = null;
}

final waypointPlacementProvider = NotifierProvider<WaypointPlacement, WaypointData?>(WaypointPlacement.new);
