import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoint_form_sheet.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';
import 'waypoints_controller.dart';

/// Shows the view/edit/delete bottom sheet for a waypoint. Shared between the
/// map screen (tapping a pin) and the waypoints list screen (tapping a row).
Future<void> showWaypointDetails(BuildContext context, WidgetRef ref, Waypoint waypoint) async {
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

  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    await editWaypoint(context, ref, waypoint);
  } else if (action == 'delete') {
    await deleteWaypoint(context, ref, waypoint);
  }
}

Future<void> editWaypoint(BuildContext context, WidgetRef ref, Waypoint waypoint) async {
  final result = await showWaypointFormSheet(context, existing: waypoint);
  if (result == null || !context.mounted) return;
  try {
    await ref.read(waypointsControllerProvider.notifier).updateWaypoint(
          waypoint.id,
          name: result.name,
          type: result.type,
          note: result.note,
          color: result.color,
        );
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> deleteWaypoint(BuildContext context, WidgetRef ref, Waypoint waypoint) async {
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
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(waypointsControllerProvider.notifier).deleteWaypoint(waypoint.id);
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
