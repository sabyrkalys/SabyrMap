import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/icon_library_scanner.dart';
import '../icons/waypoint_icon_assignments_controller.dart';
import '../map/map_crosshair.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoints_controller.dart';

/// Opens the new-waypoint form and creates the waypoint at the map's
/// crosshair. Shared by the map's «Метка здесь» button and the МЕТКИ panel.
Future<void> createWaypointAtCrosshair(BuildContext context, WidgetRef ref, {IconLibraryScanner? iconScanner}) async {
  final coordinates = ref.read(mapCrosshairProvider);
  if (coordinates == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final result = await showWaypointFormSheet(context, iconScanner: iconScanner);
  if (result == null || !context.mounted) return;
  try {
    final created = await ref.read(waypointsControllerProvider.notifier).createWaypoint(
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
      // Same reasoning as editWaypoint/deleteWaypoint in waypoint_actions.dart.
    }
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
