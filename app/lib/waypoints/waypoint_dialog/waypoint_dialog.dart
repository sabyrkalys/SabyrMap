import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../app/landmark_services_provider.dart';
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
import 'more_properties_sheet.dart';
import 'waypoint_property.dart';
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

/// Opens «Набор точек»: the waypoint dialog without coordinates (the
/// points are drawn on the map afterwards), with the set's «Ещё...».
Future<WaypointData?> showSetDialog(BuildContext context, {IconLibraryScanner? iconScanner}) {
  return showDialog<WaypointData>(
    context: context,
    builder: (_) => WaypointDialog(
      iconScanner: iconScanner,
      title: 'Набор точек',
      titleIcon: Icons.share_location_sharp,
      showCoordinates: false,
      properties: setProperties,
    ),
  );
}

/// «Путевая точка»: name, where it goes, its group, then icon (flag), colour
/// (palette), description (pencil) and «ЕЩЁ...» for the rest. The same
/// dialog, titled «Набор точек» and without [showCoordinates], creates a
/// set ([showSetDialog]).
class WaypointDialog extends ConsumerStatefulWidget {
  const WaypointDialog({
    super.key,
    this.iconScanner,
    this.pointLabel = 'Координаты центра экрана',
    this.fixedPoint,
    this.title = 'Путевая точка',
    this.titleIcon = Icons.location_on_sharp,
    this.showCoordinates = true,
    this.properties = waypointProperties,
  });

  final IconLibraryScanner? iconScanner;
  final String pointLabel;
  final LatLng? fixedPoint;
  final String title;
  final IconData titleIcon;

  /// The «Координаты центра экрана» block; a set has no single point.
  final bool showCoordinates;

  /// The rows of «Ещё...».
  final List<WaypointProperty> properties;

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

  // The chosen icon's caption, «Bunker» until the user rewrites it.
  final _iconLabel = TextEditingController();
  bool _iconLabelTouched = false;

  // ARGB of the chosen colour; null keeps the type's colour.
  int? _colorValue;

  // The chosen colour as #AARRGGBB, editable by hand.
  final _hex = TextEditingController();
  final _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Leaving the field with something that isn't a colour puts the colour back.
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) _restoreHex();
    });
  }

  String _type = defaultWaypointType;

  // «Комментарий» (the pencil) and «Описание» («Ещё...»), each shown on its own.
  bool _commentVisible = false;
  bool _descriptionVisible = false;
  final _comment = TextEditingController();
  final _description = TextEditingController();
  final _commentFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  // «Сайт» and «Ключевые слова» from «Ещё...».
  bool _websiteVisible = false;
  bool _keywordsVisible = false;
  final _website = TextEditingController();
  final _keywords = TextEditingController();
  final _websiteFocus = FocusNode();
  final _keywordsFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _iconLabel.dispose();
    _hex.dispose();
    _hexFocus.dispose();
    _comment.dispose();
    _description.dispose();
    _commentFocus.dispose();
    _descriptionFocus.dispose();
    _website.dispose();
    _keywords.dispose();
    _websiteFocus.dispose();
    _keywordsFocus.dispose();
    super.dispose();
  }

  Color get _effectiveColor => _colorValue != null
      ? Color(_colorValue!)
      : colorFromHex(waypointTypeColors[_type] ?? waypointTypeColors[defaultWaypointType]!);

  Future<void> _pickIcon() async {
    final result = await showMarkerIconSheet(context, currentIconId: _icon?.id, scanner: widget.iconScanner);
    if (result == null || !mounted) return;
    setState(() {
      if (result.id == noneOption.id) {
        _icon = null;
        _iconLabel.clear();
        _iconLabelTouched = false;
      } else {
        _icon = result;
        // A caption the user typed survives choosing another icon.
        if (!_iconLabelTouched) _iconLabel.text = result.label;
      }
    });
  }

  Future<void> _pickColor() async {
    final pick = await showWaypointColorPicker(context, _effectiveColor);
    if (pick == null || !mounted) return;
    setState(() {
      _colorValue = pick.reset ? null : pick.color.toARGB32();
      // The field shows the colour that was just picked.
      _hex.text = _colorValue == null ? '' : argbHex(_colorValue!);
    });
  }

  /// Typing in the HEX field: a whole #AARRGGBB is the new colour,
  /// anything else leaves the colour as it was; an empty field drops it.
  void _onHexChanged(String text) {
    if (text.trim().isEmpty) {
      setState(() => _colorValue = null);
      return;
    }
    final value = parseArgbHex(text);
    if (value != null) setState(() => _colorValue = value);
  }

  void _restoreHex() {
    final value = _colorValue;
    if (value != null && parseArgbHex(_hex.text) != value) _hex.text = argbHex(value);
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

  /// Shows a field and puts the cursor in it. Autofocus alone won't do:
  /// «Имя» already has the focus when the field appears.
  void _show(VoidCallback reveal, FocusNode focus) {
    setState(reveal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  Future<void> _onMoreProperties() async {
    final selected = await showMorePropertiesSheet(context, properties: widget.properties);
    if (selected == null || !mounted) return;
    switch (selected) {
      case WaypointPropertyType.icon:
        await _pickIcon();
      case WaypointPropertyType.color:
        await _pickColor();
      case WaypointPropertyType.website:
        _show(() => _websiteVisible = true, _websiteFocus);
      case WaypointPropertyType.keywords:
        _show(() => _keywordsVisible = true, _keywordsFocus);
      case WaypointPropertyType.style:
        await _pickType();
      case WaypointPropertyType.description:
        _show(() => _descriptionVisible = true, _descriptionFocus);
      case WaypointPropertyType.comment:
        _show(() => _commentVisible = true, _commentFocus);
      case WaypointPropertyType.image ||
          WaypointPropertyType.gallery ||
          WaypointPropertyType.audio ||
          WaypointPropertyType.course:
        // Not stored by the app or the server yet.
        debugPrint('Property selected: $selected');
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

  void _pickGroup(MarkerGroup group) {
    if (group.id == MarkerGroup.allId) {
      setState(() => _groupExpanded = false);
      ref.read(allMarkersOpenerProvider)(context);
      return;
    }
    setState(() {
      _groupId = group.id;
      _groupExpanded = false;
    });
  }

  /// The group row: a tap folds out a raised white panel of the groups
  /// with their storage paths, and folds it back in.
  Widget _groupSection() {
    final groups = builtInMarkerGroups(ref.watch(markerGroupFoldersProvider));
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

  /// The chosen icon: its caption to edit, and the icon itself, which
  /// opens «Иконка» again.
  Widget _iconRow(MarkerIcon icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const Key('waypoint_dialog_icon_label'),
            controller: _iconLabel,
            onChanged: (_) => _iconLabelTouched = true,
            style: const TextStyle(fontSize: 16, color: _textColor),
            cursorColor: _accent,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: const Color(0xFFE4E8ED),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: const Key('waypoint_dialog_icon_preview'),
            onTap: _pickIcon,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 56,
              height: 44,
              child: Center(child: MarkerIconGlyph(icon: icon, size: 24, dotSize: 14)),
            ),
          ),
        ),
      ],
    );
  }

  /// The chosen colour: its #AARRGGBB to edit, and a swatch that opens
  /// the colour picker again.
  Widget _colorRow(Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const Key('waypoint_dialog_color_hex'),
            controller: _hex,
            focusNode: _hexFocus,
            onChanged: _onHexChanged,
            onSubmitted: (_) => _restoreHex(),
            style: const TextStyle(fontSize: 16, color: _textColor, fontWeight: FontWeight.w400),
            cursorColor: _accent,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: const Color(0xFFE4E8ED),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: const Key('waypoint_dialog_color_preview'),
            onTap: _pickColor,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 56,
              height: 44,
              child: Center(
                child: Container(
                  key: const Key('waypoint_dialog_color_swatch'),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    // A light colour would vanish on the grey.
                    border: color.computeLuminance() > 0.8 ? Border.all(color: const Color(0xFFBDBDBD)) : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// «Комментарий»: one line under a label, an underline below.
  Widget _commentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Комментарий', style: TextStyle(fontSize: 15, color: _textColor)),
        TextField(
          key: const Key('waypoint_dialog_comment'),
          controller: _comment,
          focusNode: _commentFocus,
          maxLines: 1,
          style: const TextStyle(fontSize: 16, color: _textColor),
          cursorColor: _accent,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ],
    );
  }

  /// «Сайт» / «Ключевые слова»: one line under a label, like «Комментарий».
  Widget _lineField(String label, Key key, TextEditingController controller, FocusNode focus, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, color: _textColor)),
        TextField(
          key: key,
          controller: controller,
          focusNode: focus,
          maxLines: 1,
          keyboardType: key == const Key('waypoint_dialog_website') ? TextInputType.url : TextInputType.text,
          style: const TextStyle(fontSize: 16, color: _textColor),
          cursorColor: _accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ],
    );
  }

  /// «Описание»: a label over a borderless block of at least five lines,
  /// a thin line under it.
  Widget _descriptionField() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Описание', style: TextStyle(fontSize: 15, color: _textColor)),
          TextField(
            key: const Key('waypoint_dialog_description'),
            controller: _description,
            focusNode: _descriptionFocus,
            minLines: 5,
            maxLines: null,
            maxLength: 500,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 15, color: _textColor),
            cursorColor: _accent,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const Divider(color: Color(0xFFBDBDBD), height: 1),
        ],
      ),
    );
  }

  void _ok() => Navigator.of(context).pop(
    WaypointData(
      name: _name.text.trim(),
      point: _enteredPoint,
      groupId: _groupId,
      iconId: _icon?.fileName,
      markerIconId: _icon == null || _icon!.isFile ? null : _icon!.id,
      iconLabel: _icon == null ? null : _iconLabel.text.trim(),
      colorValue: _colorValue,
      type: _type,
      // «Описание» is the waypoint's note on the server.
      note: _descriptionVisible ? _description.text.trim() : '',
      comment: _commentVisible ? _comment.text.trim() : null,
      website: _websiteVisible ? _website.text.trim() : null,
      keywords: _keywordsVisible ? _keywords.text.trim() : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const buttonStyle = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5);
    return AlertDialog(
      key: Key(widget.showCoordinates ? 'waypoint_dialog' : 'set_dialog'),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Icon(widget.titleIcon, size: 24, color: _iconColor),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _textColor),
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
            if (widget.showCoordinates) ...[_coordsSection(), const SizedBox(height: 16)],
            _groupSection(),
            const SizedBox(height: 24),
            if (_icon case final icon?) ...[_iconRow(icon), const SizedBox(height: 16)],
            if (_colorValue case final color?) ...[_colorRow(Color(color)), const SizedBox(height: 16)],
            if (_commentVisible) ...[_commentField(), const SizedBox(height: 16)],
            if (_websiteVisible) ...[
              _lineField('Сайт', const Key('waypoint_dialog_website'), _website, _websiteFocus, hint: 'https://'),
              const SizedBox(height: 16),
            ],
            if (_keywordsVisible) ...[
              _lineField(
                'Ключевые слова',
                const Key('waypoint_dialog_keywords'),
                _keywords,
                _keywordsFocus,
                hint: 'через запятую',
              ),
              const SizedBox(height: 16),
            ],
            if (_descriptionVisible) ...[_descriptionField(), const SizedBox(height: 16)],
            Row(
              children: [
                // A chosen icon or colour has its own row above instead of
                // its button here.
                if (_icon == null) ...[
                  ActionButton(key: const Key('waypoint_dialog_icon'), icon: Icons.flag_sharp, onTap: _pickIcon),
                  const SizedBox(width: 8),
                ],
                if (_colorValue == null) ...[
                  ActionButton(key: const Key('waypoint_dialog_color'), icon: Icons.palette_sharp, onTap: _pickColor),
                  const SizedBox(width: 8),
                ],
                if (!_commentVisible && !_descriptionVisible) ...[
                  ActionButton(
                    key: const Key('waypoint_dialog_note'),
                    icon: Icons.edit_sharp,
                    onTap: () => _show(() => _commentVisible = true, _commentFocus),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: WideActionButton(
                    key: const Key('waypoint_dialog_more'),
                    label: 'ЕЩЁ...',
                    onTap: _onMoreProperties,
                  ),
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
