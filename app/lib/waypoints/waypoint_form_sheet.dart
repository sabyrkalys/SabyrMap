import 'package:flutter/material.dart';

import 'waypoint_models.dart';
import 'waypoint_types.dart';

class WaypointFormResult {
  const WaypointFormResult({required this.name, required this.type, required this.note});

  final String name;
  final String type;
  final String note;
}

Future<WaypointFormResult?> showWaypointFormSheet(BuildContext context, {Waypoint? existing}) {
  return showModalBottomSheet<WaypointFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => WaypointFormSheet(existing: existing),
  );
}

class WaypointFormSheet extends StatefulWidget {
  const WaypointFormSheet({super.key, this.existing});

  final Waypoint? existing;

  @override
  State<WaypointFormSheet> createState() => _WaypointFormSheetState();
}

class _WaypointFormSheetState extends State<WaypointFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _noteController =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _selectedType = widget.existing?.type ?? defaultWaypointType;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEditing ? 'Редактировать метку' : 'Новая метка', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final type in waypointTypes)
                ChoiceChip(
                  key: Key('waypoint_type_chip_$type'),
                  label: Text(waypointTypeLabels[type] ?? type),
                  selected: _selectedType == type,
                  onSelected: (_) => setState(() => _selectedType = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('waypoint_note_field'),
            controller: _noteController,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Заметка (необязательно)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('waypoint_save_button'),
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      WaypointFormResult(
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        note: _noteController.text.trim(),
                      ),
                    ),
            child: Text(isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }
}
