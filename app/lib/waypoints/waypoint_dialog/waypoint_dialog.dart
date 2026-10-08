import 'package:flutter/material.dart';

import '../../icons/icon_library_scanner.dart';
import '../../icons/icon_picker_sheet.dart';
import '../waypoint_color.dart';
import '../waypoint_color_picker.dart';
import '../waypoint_types.dart';
import 'action_button.dart';
import 'dropdown_field.dart';
import 'more_sheet.dart';
import 'waypoint_data.dart';

const Color _accent = Color(0xFF00A38E);
const Color _textColor = Color(0xFF212121);
const Color _iconColor = Color(0xFF333333);

/// Opens the «Путевая точка» dialog. Completes with what was entered on
/// «ОК», or null on «ОТМЕНА». [pointLabel] names the place the waypoint
/// goes by default (the screen centre, or the «Задать цель» target).
Future<WaypointData?> showWaypointDialog(
  BuildContext context, {
  IconLibraryScanner? iconScanner,
  String pointLabel = 'Координаты центра экрана',
}) {
  return showDialog<WaypointData>(
    context: context,
    builder: (_) => WaypointDialog(iconScanner: iconScanner, pointLabel: pointLabel),
  );
}

/// «Путевая точка»: name, where it goes, its group, then icon (flag), colour
/// (palette), description (pencil) and «ЕЩЁ...» for the rest.
class WaypointDialog extends StatefulWidget {
  const WaypointDialog({super.key, this.iconScanner, this.pointLabel = 'Координаты центра экрана'});

  final IconLibraryScanner? iconScanner;
  final String pointLabel;

  @override
  State<WaypointDialog> createState() => _WaypointDialogState();
}

class _WaypointDialogState extends State<WaypointDialog> {
  final _name = TextEditingController();
  WaypointCoords _coords = WaypointCoords.screenCenter;
  String _groupId = WaypointData.unsortedGroupId;
  String? _iconId;
  int? _colorValue;
  String _type = defaultWaypointType;
  String _note = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Color get _effectiveColor => _colorValue != null
      ? Color(_colorValue!)
      : colorFromHex(waypointTypeColors[_type] ?? waypointTypeColors[defaultWaypointType]!);

  Future<void> _pickIcon() async {
    final result = await showIconPickerSheet(context, scanner: widget.iconScanner);
    if (result != null && mounted) setState(() => _iconId = result.fileName);
  }

  Future<void> _pickColor() async {
    final pick = await showWaypointColorPicker(context, _effectiveColor);
    if (pick != null && mounted) setState(() => _colorValue = pick.reset ? null : pick.color.toARGB32());
  }

  Future<void> _editNote() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: _note),
    );
    if (note != null && mounted) setState(() => _note = note);
  }

  Future<void> _pickType() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Стиль'),
        children: [
          for (final type in waypointTypes)
            SimpleDialogOption(
              key: Key('waypoint_dialog_type_$type'),
              onPressed: () => Navigator.of(context).pop(type),
              child: Row(
                children: [
                  CircleAvatar(radius: 8, backgroundColor: colorFromHex(waypointTypeColors[type]!)),
                  const SizedBox(width: 12),
                  Text(waypointTypeLabels[type] ?? type, style: const TextStyle(fontSize: 16)),
                  if (type == _type) ...[const Spacer(), const Icon(Icons.check_sharp, size: 20)],
                ],
              ),
            ),
        ],
      ),
    );
    if (type != null && mounted) setState(() => _type = type);
  }

  Future<void> _more() async {
    final extra = await showWaypointMoreSheet(context);
    if (extra == null || !mounted) return;
    switch (extra) {
      case WaypointExtra.color:
        await _pickColor();
      case WaypointExtra.style:
        await _pickType();
      case WaypointExtra.description:
        await _editNote();
      case WaypointExtra.image ||
          WaypointExtra.gallery ||
          WaypointExtra.audio ||
          WaypointExtra.course ||
          WaypointExtra.website ||
          WaypointExtra.keywords:
        // Not stored by the app or the server yet.
        debugPrint('Waypoint extra: ${extra.name}');
    }
  }

  void _ok() => Navigator.of(context).pop(
    WaypointData(
      name: _name.text.trim(),
      coords: _coords,
      groupId: _groupId,
      iconId: _iconId,
      colorValue: _colorValue,
      type: _type,
      note: _note,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const buttonStyle = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5);
    return AlertDialog(
      key: const Key('waypoint_dialog'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: EdgeInsets.symmetric(horizontal: width * 0.075, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Icon(Icons.location_on_sharp, size: 24, color: _iconColor),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Путевая точка',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _textColor),
                    ),
                  ),
                ],
              ),
            ),
            const Text('Имя', style: TextStyle(fontSize: 12, color: _accent, letterSpacing: 0.5)),
            TextField(
              key: const Key('waypoint_dialog_name_field'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, color: _textColor),
              cursorColor: _accent,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),
            DropdownField<WaypointCoords>(
              key: const Key('waypoint_dialog_coords'),
              icon: Icons.my_location_sharp,
              value: _coords,
              options: [
                (WaypointCoords.screenCenter, widget.pointLabel),
                (WaypointCoords.customPoint, 'Указать точку на карте'),
              ],
              onChanged: (coords) => setState(() => _coords = coords),
            ),
            const SizedBox(height: 16),
            DropdownField<String>(
              key: const Key('waypoint_dialog_group'),
              icon: Icons.bookmark_sharp,
              value: _groupId,
              options: const [(WaypointData.unsortedGroupId, 'Несортированные метки')],
              onChanged: (group) => setState(() => _groupId = group),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ActionButton(key: const Key('waypoint_dialog_icon'), icon: Icons.flag_sharp, onTap: _pickIcon),
                const SizedBox(width: 8),
                ActionButton(
                  key: const Key('waypoint_dialog_color'),
                  icon: Icons.palette_sharp,
                  iconColor: _colorValue != null ? _effectiveColor : _iconColor,
                  onTap: _pickColor,
                ),
                const SizedBox(width: 8),
                ActionButton(key: const Key('waypoint_dialog_note'), icon: Icons.edit_sharp, onTap: _editNote),
                const SizedBox(width: 8),
                Expanded(
                  child: WideActionButton(key: const Key('waypoint_dialog_more'), label: 'ЕЩЁ...', onTap: _more),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('waypoint_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: _accent),
          child: const Text('ОТМЕНА', style: buttonStyle),
        ),
        TextButton(
          key: const Key('waypoint_dialog_ok'),
          onPressed: _ok,
          style: TextButton.styleFrom(foregroundColor: _accent),
          child: const Text('ОК', style: buttonStyle),
        ),
      ],
    );
  }
}

/// «Описание»: the waypoint's note. Completes with the text on «ОК».
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Описание'),
      content: TextField(
        key: const Key('waypoint_dialog_note_field'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 4,
        minLines: 1,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОТМЕНА')),
        TextButton(
          key: const Key('waypoint_dialog_note_ok'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('ОК'),
        ),
      ],
    );
  }
}
