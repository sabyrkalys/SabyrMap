import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// How the waypoint colour picker was closed: a colour chosen, or «Сбросить»
/// back to the type's colour. Null from [showWaypointColorPicker] is «Отмена».
typedef WaypointColorPick = ({bool reset, Color color});

Future<WaypointColorPick?> showWaypointColorPicker(BuildContext context, Color initial) async {
  Color picked = initial;
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
        TextButton(onPressed: () => Navigator.of(dialogContext).pop('cancel'), child: const Text('Отмена')),
        FilledButton(
          key: const Key('waypoint_color_picker_select_button'),
          onPressed: () => Navigator.of(dialogContext).pop('select'),
          child: const Text('Выбрать'),
        ),
      ],
    ),
  );
  return switch (action) {
    'select' => (reset: false, color: picked),
    'reset' => (reset: true, color: initial),
    _ => null,
  };
}
