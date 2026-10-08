import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../map/sk42.dart';
import 'coords_system.dart';

const Color _accent = Color(0xFF00A38E);
const Color _textColor = Color(0xFF212121);
const Color _lineColor = Color(0xFFBDBDBD);

/// Opens «Координаты» over the waypoint dialog, filled with [initial] in
/// [system]. Completes with the entered coordinates on «ОК», or null on
/// «ОТМЕНА» or a tap outside.
Future<CoordinatesResult?> showCoordinatesDialog(
  BuildContext context, {
  required LatLng initial,
  CoordsSystem system = CoordsSystem.sk42,
}) {
  return showDialog<CoordinatesResult>(
    context: context,
    builder: (_) => CoordinatesDialog(initial: initial, system: system),
  );
}

/// «Координаты»: the system (latitude/longitude or СК-42), then X and Y as
/// two fields or, with «Единое поле», one field to copy or paste.
class CoordinatesDialog extends StatefulWidget {
  const CoordinatesDialog({super.key, required this.initial, this.system = CoordsSystem.sk42});

  final LatLng initial;
  final CoordsSystem system;

  @override
  State<CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<CoordinatesDialog> {
  late CoordsSystem _system = widget.system;
  final _x = TextEditingController();
  final _y = TextEditingController();
  final _single = TextEditingController();
  bool _singleField = false;

  // Hemispheres of the latitude/longitude fields, which hold unsigned degrees.
  bool _north = true;
  bool _east = true;

  @override
  void initState() {
    super.initState();
    _fill(widget.initial);
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _single.dispose();
    super.dispose();
  }

  /// Writes [point] into the fields in the current system.
  void _fill(LatLng point) {
    switch (_system) {
      case CoordsSystem.wgs84:
        _x.text = formatDegrees(point.latitude);
        _y.text = formatDegrees(point.longitude);
        _north = point.latitude >= 0;
        _east = point.longitude >= 0;
      case CoordsSystem.sk42:
        final p = toSk42(point.latitude, point.longitude);
        _x.text = p.x.round().toString();
        _y.text = p.y.round().toString();
    }
    if (_singleField) _single.text = _merged();
  }

  /// The two fields as one line: «X=5318818 Y=7411502» or «47.993239°N 37.801170°E».
  String _merged() => switch (_system) {
    CoordsSystem.wgs84 => '${_x.text.trim()}°${_north ? 'N' : 'S'} ${_y.text.trim()}°${_east ? 'E' : 'W'}',
    CoordsSystem.sk42 => 'X=${_x.text.trim()} Y=${_y.text.trim()}',
  };

  /// What is entered now, in the current system; null when it isn't two numbers.
  CoordinatesResult? _read() {
    final (double, double)? pair;
    if (_singleField) {
      pair = _system == CoordsSystem.wgs84 ? parseLatLngPair(_single.text) : parseCoordinatePair(_single.text);
    } else {
      pair = switch ((_number(_x.text), _number(_y.text))) {
        (final double x, final double y) when _system == CoordsSystem.wgs84 => (
          _north ? x.abs() : -x.abs(),
          _east ? y.abs() : -y.abs(),
        ),
        (final double x, final double y) => (x, y),
        _ => null,
      };
    }
    return pair == null ? null : CoordinatesResult(system: _system, x: pair.$1, y: pair.$2);
  }

  /// Switches the system and converts what is entered into it; anything
  /// that isn't a valid point stays as it was.
  void _setSystem(CoordsSystem system) {
    if (system == _system) return;
    final current = _read();
    setState(() {
      _system = system;
      if (current != null && current.isValid) _fill(current.point);
    });
  }

  /// Merges the two fields into one, or splits it back when it holds two numbers.
  void _toggleSingleField(bool single) {
    final current = single ? null : _read();
    setState(() {
      if (single) {
        _single.text = _merged();
      } else if (current != null) {
        if (_system == CoordsSystem.wgs84) {
          _x.text = formatDegrees(current.x);
          _y.text = formatDegrees(current.y);
          _north = current.x >= 0;
          _east = current.y >= 0;
        } else {
          _x.text = _plain(current.x);
          _y.text = _plain(current.y);
        }
      }
      _singleField = single;
    });
  }

  /// 5318818.0 → «5318818»; other numbers as they are.
  static String _plain(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  void _ok() {
    final result = _read();
    if (result == null || !result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Некорректные координаты')));
      return;
    }
    Navigator.of(context).pop(result);
  }

  static double? _number(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  Widget _systemOption(CoordsSystem system) {
    final selected = _system == system;
    return GestureDetector(
      key: Key('coords_system_${system.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _setSystem(system),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          // Only СК-42 is highlighted when chosen, as in the mockup.
          color: selected && system == CoordsSystem.sk42 ? const Color(0xFFE0E0E0) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Radio<CoordsSystem>(value: system, activeColor: _accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(system.label, style: const TextStyle(fontSize: 16, color: _textColor)),
            ),
          ],
        ),
      ),
    );
  }

  static const _underline = InputDecoration(
    isDense: true,
    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _lineColor)),
    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
  );

  Widget _input(TextEditingController controller, {required Key key, required bool signed, bool autofocus = false}) {
    return TextField(
      key: key,
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(signed: signed, decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(signed ? r'[0-9.,\-]' : r'[0-9.,]'))],
      style: const TextStyle(fontSize: 16, color: _textColor),
      cursorColor: _accent,
      decoration: _underline,
    );
  }

  /// «X = ____» for СК-42.
  Widget _gridField(String label, TextEditingController controller, {required Key key, bool autofocus = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 18, color: _textColor, fontWeight: FontWeight.w400),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _input(controller, key: key, signed: true, autofocus: autofocus),
        ),
      ],
    );
  }

  /// «____ ° [N]» for latitude/longitude: unsigned degrees and a button
  /// that flips the hemisphere.
  Widget _degreesField(
    TextEditingController controller, {
    required Key key,
    required Key hemisphereKey,
    required String hemisphere,
    required VoidCallback onFlip,
    bool autofocus = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: _input(controller, key: key, signed: false, autofocus: autofocus),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('°', style: TextStyle(fontSize: 18, color: _textColor)),
        ),
        Material(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(4),
          elevation: 1,
          child: InkWell(
            key: hemisphereKey,
            onTap: onFlip,
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 48,
              height: 44,
              child: Center(
                child: Text(hemisphere, style: const TextStyle(fontSize: 18, color: _textColor)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const buttonStyle = TextStyle(fontWeight: FontWeight.w600);
    return AlertDialog(
      key: const Key('coordinates_dialog'),
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
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                'Координаты',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _textColor),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Критерий поиска', style: TextStyle(fontSize: 13, color: _accent, letterSpacing: 0.3)),
            ),
            RadioGroup<CoordsSystem>(
              groupValue: _system,
              onChanged: (system) => _setSystem(system ?? _system),
              child: Column(
                children: [
                  _systemOption(CoordsSystem.wgs84),
                  const SizedBox(height: 8),
                  _systemOption(CoordsSystem.sk42),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_singleField)
              TextField(
                key: const Key('coords_single_field'),
                controller: _single,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 16, color: _textColor),
                cursorColor: _accent,
                decoration: _underline,
              )
            else if (_system == CoordsSystem.wgs84) ...[
              _degreesField(
                _x,
                key: const Key('coords_x_field'),
                hemisphereKey: const Key('coords_lat_hemisphere'),
                hemisphere: _north ? 'N' : 'S',
                onFlip: () => setState(() => _north = !_north),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _degreesField(
                _y,
                key: const Key('coords_y_field'),
                hemisphereKey: const Key('coords_lng_hemisphere'),
                hemisphere: _east ? 'E' : 'W',
                onFlip: () => setState(() => _east = !_east),
              ),
            ] else ...[
              _gridField('X =', _x, key: const Key('coords_x_field'), autofocus: true),
              const SizedBox(height: 12),
              _gridField('Y =', _y, key: const Key('coords_y_field')),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleSingleField(!_singleField),
              child: Row(
                children: [
                  Checkbox(
                    key: const Key('coords_single_checkbox'),
                    value: _singleField,
                    activeColor: _accent,
                    onChanged: (value) => _toggleSingleField(value ?? false),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Единое поле (для копирования/вставки)',
                      style: TextStyle(fontSize: 15, color: _textColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('coords_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: _accent),
          child: const Text('ОТМЕНА', style: buttonStyle),
        ),
        TextButton(
          key: const Key('coords_ok'),
          onPressed: _ok,
          style: TextButton.styleFrom(foregroundColor: _accent),
          child: const Text('ОК', style: buttonStyle),
        ),
      ],
    );
  }
}
