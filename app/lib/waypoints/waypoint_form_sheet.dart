import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' hide colorFromHex, colorToHex;

import '../icons/icon_library_scanner.dart';
import '../icons/icon_picker_sheet.dart';
import 'waypoint_color.dart';
import 'waypoint_models.dart';
import 'waypoint_types.dart';

class WaypointFormResult {
  const WaypointFormResult({
    required this.name,
    required this.type,
    required this.note,
    required this.color,
    required this.iconFileName,
  });

  final String name;
  final String type;
  final String note;
  final String? color;
  final String? iconFileName;
}

Future<WaypointFormResult?> showWaypointFormSheet(
  BuildContext context, {
  Waypoint? existing,
  String? initialIconFileName,
  IconLibraryScanner? iconScanner,
}) {
  return showModalBottomSheet<WaypointFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => WaypointFormSheet(
      existing: existing,
      initialIconFileName: initialIconFileName,
      iconScanner: iconScanner,
    ),
  );
}

class WaypointFormSheet extends StatefulWidget {
  const WaypointFormSheet({super.key, this.existing, this.initialIconFileName, this.iconScanner});

  final Waypoint? existing;
  final String? initialIconFileName;
  final IconLibraryScanner? iconScanner;

  @override
  State<WaypointFormSheet> createState() => _WaypointFormSheetState();
}

class _WaypointFormSheetState extends State<WaypointFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _noteController =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _selectedType = widget.existing?.type ?? defaultWaypointType;
  String? _selectedColor;
  String? _selectedIconFileName;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.existing?.color;
    _selectedIconFileName = widget.initialIconFileName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _effectiveColorHex =>
      _selectedColor ?? waypointTypeColors[_selectedType] ?? waypointTypeColors[defaultWaypointType]!;

  bool get _colorPickerVisible => _selectedIconFileName == null || _selectedIconFileName!.toLowerCase().endsWith('.svg');

  Future<void> _openColorPicker() async {
    Color picked = colorFromHex(_effectiveColorHex);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (color) => picked = color,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('waypoint_color_picker_reset_button'),
            onPressed: () => Navigator.of(dialogContext).pop('reset'),
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('waypoint_color_picker_select_button'),
            onPressed: () => Navigator.of(dialogContext).pop('select'),
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );

    if (action == 'select') {
      setState(() => _selectedColor = colorToHex(picked));
    } else if (action == 'reset') {
      setState(() => _selectedColor = null);
    }
  }

  Future<void> _openIconPicker() async {
    final result = await showIconPickerSheet(context, scanner: widget.iconScanner);
    if (result == null) return;
    setState(() => _selectedIconFileName = result.fileName);
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
          Row(
            children: [
              const Text('Иконка'),
              const SizedBox(width: 12),
              OutlinedButton(
                key: const Key('waypoint_icon_button'),
                onPressed: _openIconPicker,
                child: Text(_selectedIconFileName ?? 'Стандартная'),
              ),
            ],
          ),
          if (_colorPickerVisible) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Цвет'),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _openColorPicker,
                  child: Container(
                    key: const Key('waypoint_color_swatch'),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorFromHex(_effectiveColorHex),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                        color: _selectedColor,
                        iconFileName: _selectedIconFileName,
                      ),
                    ),
            child: Text(isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }
}
