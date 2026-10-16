import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/icon_library_scanner.dart';
import 'waypoint_edits.dart';
import 'waypoint_form_sheet.dart';
import 'waypoint_types.dart';

/// Карточка путевой точки [item]: просмотр, правка, удаление. Её
/// открывает нажатие по точке на карте. Точку внутри файла меток только
/// показывает.
Future<void> showWaypointDetails(BuildContext context, WidgetRef ref, LandmarkItem item) async {
  final type = item.kind ?? defaultWaypointType;
  final note = item.description;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(waypointTypeLabels[type] ?? type),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(note),
          ],
          if (!item.isNested) ...[
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
    await editWaypoint(context, ref, item);
  } else if (action == 'delete') {
    await deleteWaypoint(context, ref, item);
  }
}

Future<void> editWaypoint(BuildContext context, WidgetRef ref, LandmarkItem item, {IconLibraryScanner? iconScanner}) async {
  final result = await showWaypointFormSheet(context, existing: item, iconScanner: iconScanner);
  if (result == null || !context.mounted) return;
  try {
    await ref.read(waypointEditsProvider).update(
          item.path,
          name: result.name,
          type: result.type,
          note: result.note,
          color: result.color,
          iconFileName: result.iconFileName,
        );
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> deleteWaypoint(BuildContext context, WidgetRef ref, LandmarkItem item) async {
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
    await ref.read(waypointEditsProvider).delete(item.path);
  } on WaypointException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
