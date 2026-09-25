import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import '../map/map_crosshair.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoints_controller.dart';

/// Opens the new-waypoint form and creates the waypoint at the map's
/// crosshair. Shared by the crosshair menu and the МЕТКИ panel.
///
/// The panel can be closed while the request is in flight, which unmounts
/// [context] and disposes [ref]; the container and messenger are captured
/// up front so the result is still applied and reported.
Future<void> createWaypointAtCrosshair(BuildContext context, WidgetRef ref, {IconLibraryScanner? iconScanner}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final coordinates = ref.read(mapCrosshairProvider);
  if (coordinates == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final result = await showWaypointFormSheet(context, iconScanner: iconScanner);
  if (result == null) return;
  try {
    final created = await container.read(waypointsControllerProvider.notifier).createWaypoint(
          name: result.name,
          type: result.type,
          note: result.note,
          color: result.color,
          lat: coordinates.latitude,
          lng: coordinates.longitude,
        );
    try {
      await container.read(waypointIconAssignmentsControllerProvider.notifier).setIcon(created.id, result.iconFileName);
    } catch (_) {
      // The waypoint itself was created; a local icon-bookkeeping failure
      // is a soft failure and shouldn't be reported as a failed creation.
      // Same reasoning as editWaypoint/deleteWaypoint in waypoint_actions.dart.
    }
  } on WaypointException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
