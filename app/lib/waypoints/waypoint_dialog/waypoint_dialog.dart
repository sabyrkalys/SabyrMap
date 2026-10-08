import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../icons/icon_library_scanner.dart';
import '../../map/map_crosshair.dart';
import '../waypoint_color.dart';
import '../waypoint_color_picker.dart';
import '../waypoint_types.dart';
import '../icon_picker/icon_item.dart';
import '../icon_picker/icon_picker_sheet.dart';
import '../icon_picker/marker_icon.dart';
import 'action_button.dart';
import 'coordinates_dialog.dart';
import 'coords_system.dart';
import 'marker_group.dart';
import 'more_sheet.dart';
import 'waypoint_data.dart';

const Color _accent = Color(0xFF00A38E);
const Color _textColor = Color(0xFF212121);
const Color _iconColor = Color(0xFF333333);

/// Opens the «Путевая точка» dialog. Completes with what was entered on
/// «ОК», or null on «ОТМЕНА». The waypoint goes to [fixedPoint] (the
/// «Задать цель» target, named by [pointLabel]) or, without one, to the
/// map's crosshair, followed live while the dialog is open.
Future<WaypointData?> showWaypointDialog(
  BuildContext context, {
  IconLibraryScanner? iconScanner,
  String pointLabel = 'Координаты центра экрана',
  LatLng? fixedPoint,
}) {
  return showDialog<WaypointData>(
    context: context,
    builder: (_) => WaypointDialog(iconScanner: iconScanner, pointLabel: pointLabel, fixedPoint: fixedPoint),
  );
}

/// «Путевая точка»: name, where it goes, its group, then icon (flag), colour
/// (palette), description (pencil) and «ЕЩЁ...» for the rest.
class WaypointDialog extends ConsumerStatefulWidget {
  const WaypointDialog({super.key, this.iconScanner, this.pointLabel = 'Координаты центра экрана', this.fixedPoint});

  final IconLibraryScanner? iconScanner;
  final String pointLabel;
  final LatLng? fixedPoint;

  @override
  ConsumerState<WaypointDialog> createState() => _WaypointDialogState();
}

class _WaypointDialogState extends ConsumerState<WaypointDialog> {
  final _name = TextEditingController();
  bool _coordsExpanded = false;

  // Coordinates typed in «Координаты»; null follows the crosshair (or the target).
  LatLng? _enteredPoint;
  CoordsSystem _system = CoordsSystem.sk42;
  String _groupId = MarkerGroup.unsortedId;
  bool _groupExpanded = false;
  // The icon from «Иконка»; null is the standard marker.
  MarkerIcon? _icon;
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
    final result = await showMarkerIconSheet(context, currentIconId: _icon?.id, scanner: widget.iconScanner);
    if (result != null && mounted) setState(() => _icon = result.id == noneOption.id ? null : result);
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

  /// The point the waypoint goes to; [watch] in build, so the shown
  /// coordinates follow the map.
  LatLng? _pointOf({required bool watch}) =>
      _enteredPoint ?? widget.fixedPoint ?? (watch ? ref.watch(mapCrosshairProvider) : ref.read(mapCrosshairProvider));

  Future<void> _editCoordinates() async {
    final point = _pointOf(watch: false);
    if (point == null) return;
    final result = await showCoordinatesDialog(context, initial: point, system: _system);
    if (result == null || !mounted) return;
    setState(() {
      _enteredPoint = result.point;
      _system = result.system;
    });
  }

  String get _coordsTitle => _enteredPoint != null ? 'Заданные координаты' : widget.pointLabel;

  /// The coordinates row: a tap folds the block under it out or back in.
  /// Unfolded it shows the point's coordinates and «Изменить».
  Widget _coordsSection() {
    final point = _pointOf(watch: true);
    Widget action(Key key, IconData icon, String label, VoidCallback onTap, {Widget? trailing}) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 16, color: _textColor)),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('waypoint_dialog_coords'),
          onTap: () => setState(() {
            _coordsExpanded = !_coordsExpanded;
            if (_coordsExpanded) _groupExpanded = false;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.my_location_sharp, size: 20, color: _iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_coordsTitle, style: const TextStyle(fontSize: 16, color: _textColor)),
                ),
                AnimatedRotation(
                  key: const Key('waypoint_dialog_coords_chevron'),
                  turns: _coordsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_sharp, size: 20, color: Color(0xFF757575)),
                ),
              ],
            ),
          ),
        ),
        if (_coordsExpanded)
          Padding(
            key: const Key('waypoint_dialog_coords_block'),
            padding: const EdgeInsets.only(left: 32, top: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (point != null)
                  Text(
                    _system.describe(point),
                    key: const Key('waypoint_dialog_coords_value'),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
                  ),
                const Divider(height: 16, color: Color(0xFFEEEEEE)),
                action(
                  const Key('waypoint_dialog_coords_edit'),
                  Icons.edit_sharp,
                  'Изменить',
                  _editCoordinates,
                  trailing: const Icon(Icons.expand_more_sharp, size: 20, color: Color(0xFF757575)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _pickGroup(MarkerGroup group) => setState(() {
    if (group.id == MarkerGroup.allId) {
      // The list of all waypoints comes in a later iteration.
      debugPrint('Open all markers');
    } else {
      _groupId = group.id;
    }
    _groupExpanded = false;
  });

  /// The group row: a tap folds out a raised white panel of the groups
  /// with their storage paths, and folds it back in.
  Widget _groupSection() {
    final groups = builtInMarkerGroups;
    final selected = groups.firstWhere((g) => g.id == _groupId, orElse: () => groups.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('waypoint_dialog_group'),
          onTap: () => setState(() {
            _groupExpanded = !_groupExpanded;
            if (_groupExpanded) _coordsExpanded = false;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.bookmark_sharp, size: 20, color: _iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(selected.title, style: const TextStyle(fontSize: 16, color: _textColor)),
                ),
                AnimatedRotation(
                  key: const Key('waypoint_dialog_group_chevron'),
                  turns: _groupExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_sharp, size: 20, color: Color(0xFF757575)),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !_groupExpanded
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: const Key('waypoint_dialog_group_panel'),
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, group) in groups.indexed) ...[
                        if (group.sectionLabel case final label?)
                          _GroupSectionLabel(label: label)
                        else if (i > 0)
                          const SizedBox(height: 12),
                        _GroupItem(group: group, selected: group.id == _groupId, onTap: () => _pickGroup(group)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  void _ok() => Navigator.of(context).pop(
    WaypointData(
      name: _name.text.trim(),
      point: _enteredPoint,
      groupId: _groupId,
      iconId: _icon?.fileName,
      markerIconId: _icon == null || _icon!.isFile ? null : _icon!.id,
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
            _coordsSection(),
            const SizedBox(height: 16),
            _groupSection(),
            const SizedBox(height: 24),
            Row(
              children: [
                ActionButton(
                  key: const Key('waypoint_dialog_icon'),
                  icon: Icons.flag_sharp,
                  onTap: _pickIcon,
                  child: _icon == null ? null : MarkerIconGlyph(icon: _icon!, size: 24),
                ),
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

/// «— МОИ МЕТКИ»: a line, then the section's name, above its first group.
class _GroupSectionLabel extends StatelessWidget {
  const _GroupSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 16, child: Divider(height: 1, color: Color(0xFFBDBDBD))),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, color: Color(0xFF757575), letterSpacing: 0.5)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1, color: Color(0xFFBDBDBD))),
        ],
      ),
    );
  }
}

/// One group in the panel: a bullet when it is the chosen one (a folder
/// for «Все метки»), its title and, under it, where it is stored.
class _GroupItem extends StatelessWidget {
  const _GroupItem({required this.group, required this.selected, required this.onTap});

  final MarkerGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = group.subtitle;
    return InkWell(
      key: Key('waypoint_dialog_group_${group.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 22,
            child: group.id == MarkerGroup.allId
                ? const Icon(Icons.folder_sharp, size: 20, color: _iconColor)
                : selected
                ? const Center(
                    key: Key('waypoint_dialog_group_bullet'),
                    child: CircleAvatar(radius: 3.5, backgroundColor: _textColor),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: const TextStyle(fontSize: 16, color: _textColor, fontWeight: FontWeight.w400),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    softWrap: true,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF757575), height: 1.3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
