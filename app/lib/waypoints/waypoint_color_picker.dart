import 'package:flutter/material.dart';

const Color _accent = Color(0xFF00A38E);
const Color _textColor = Color(0xFF212121);
const Color _frame = Color(0xFF5A4A6A);

/// The twelve ready colours under the picker, row by row.
const List<Color> waypointPresetColors = [
  Color(0xFFEE1111),
  Color(0xFFFF00FF),
  Color(0xFF800080),
  Color(0xFF0066FF),
  Color(0xFFADD8E6),
  Color(0xFF00FFFF),
  Color(0xFF008000),
  Color(0xFF90EE90),
  Color(0xFFFFFF00),
  Color(0xFFFFA500),
  Color(0xFF888888),
  Color(0xFF000000),
];

/// How the waypoint colour picker was closed: a colour chosen, or «Сбросить»
/// back to the type's colour. Null from [showWaypointColorPicker] is «Отмена».
typedef WaypointColorPick = ({bool reset, Color color});

Future<WaypointColorPick?> showWaypointColorPicker(BuildContext context, Color initial) =>
    showDialog<WaypointColorPick>(
      context: context,
      builder: (_) => _ColorDialog(initial: initial),
    );

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  /// Hue, saturation and value are kept apart from [_color] so that dragging
  /// to black or white does not lose the hue.
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withAlpha(255));

  /// What OK returns. Only rebuilt from [_hsv] when the user moves something,
  /// so an untouched colour comes back exactly as it went in.
  late Color _color = widget.initial;

  void _setHsv(HSVColor hsv) => setState(() {
    _hsv = hsv;
    _color = hsv.toColor().withAlpha(_color.alpha8);
  });

  void _setColor(Color color) => setState(() {
    _color = color;
    _hsv = HSVColor.fromColor(color.withAlpha(255));
  });

  void _setAlpha(double opacity) => setState(() => _color = _color.withValues(alpha: opacity));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const buttonStyle = TextStyle(fontWeight: FontWeight.w600);
    final percent = (_color.a * 100).round();
    // AlertDialog measures its content's intrinsic size, which a LayoutBuilder
    // cannot give, so the sizes come from the screen width.
    final full = width * 0.9 - 40;
    final hueWidth = full * 0.12;
    final gap = full * 0.035;
    final planeWidth = full - hueWidth - gap;
    final planeHeight = planeWidth * 0.56;
    return AlertDialog(
      key: const Key('waypoint_color_picker'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: EdgeInsets.symmetric(horizontal: width * 0.05, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Цвет',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _textColor),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: planeHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: planeWidth,
                    child: _SaturationValuePlane(size: Size(planeWidth, planeHeight), hsv: _hsv, onChanged: _setHsv),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    width: hueWidth,
                    child: _HueBar(size: Size(hueWidth, planeHeight), hsv: _hsv, onChanged: _setHsv),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            Row(
              children: [
                _preview(const Key('waypoint_color_picker_new'), _color, planeWidth * 0.48),
                SizedBox(width: planeWidth * 0.04),
                GestureDetector(
                  // The old colour: tapping it goes back to it.
                  onTap: () => _setColor(widget.initial),
                  child: _preview(const Key('waypoint_color_picker_old'), widget.initial, planeWidth * 0.48),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _presets(full),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '$percent % непрозрачн.',
                key: const Key('waypoint_color_picker_opacity_label'),
                style: const TextStyle(fontSize: 15, color: Color(0xFF757575)),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _accent,
                inactiveTrackColor: _accent.withValues(alpha: 0.3),
                thumbColor: _accent,
                overlayColor: _accent.withValues(alpha: 0.12),
                trackHeight: 3,
              ),
              child: Slider(key: const Key('waypoint_color_picker_opacity'), value: _color.a, onChanged: _setAlpha),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            TextButton(
              key: const Key('waypoint_color_picker_reset_button'),
              onPressed: () => Navigator.of(context).pop((reset: true, color: widget.initial)),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('СБРОСИТЬ', style: buttonStyle),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('ОТМЕНА', style: buttonStyle),
            ),
            TextButton(
              key: const Key('waypoint_color_picker_select_button'),
              onPressed: () => Navigator.of(context).pop((reset: false, color: _color)),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('OK', style: buttonStyle),
            ),
          ],
        ),
      ],
    );
  }

  Widget _preview(Key key, Color color, double width) => Container(
    key: key,
    width: width,
    height: 44,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: _frame, width: 0.8),
    ),
  );

  Widget _presets(double full) {
    const columns = 6;
    final tileWidth = full / (columns + (columns - 1) * 0.45);
    final spacing = tileWidth * 0.45;
    return Wrap(
      spacing: spacing,
      runSpacing: tileWidth * 0.3,
      children: [
        for (final (i, color) in waypointPresetColors.indexed)
          Material(
            key: Key('waypoint_color_preset_$i'),
            color: const Color(0xFFD9D9D9),
            elevation: 2,
            borderRadius: BorderRadius.circular(3),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => _setColor(color.withAlpha(_color.alpha8)),
              child: SizedBox(
                width: tileWidth,
                height: tileWidth * 0.88,
                child: Center(
                  child: Container(
                    width: tileWidth * 0.38,
                    height: tileWidth * 0.38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 2, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

extension on Color {
  int get alpha8 => (a * 255).round();
}

/// Saturation left to right, value top to bottom, for the current hue.
class _SaturationValuePlane extends StatelessWidget {
  const _SaturationValuePlane({required this.size, required this.hsv, required this.onChanged});

  final Size size;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged(
      hsv.withSaturation((p.dx / size.width).clamp(0.0, 1.0)).withValue(1 - (p.dy / size.height).clamp(0.0, 1.0)),
    );
    return GestureDetector(
      key: const Key('waypoint_color_picker_plane'),
      onPanDown: (d) => update(d.localPosition),
      onPanUpdate: (d) => update(d.localPosition),
      child: CustomPaint(size: size, painter: _PlanePainter(hsv)),
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, hue]).createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _frame,
    );

    final cursor = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    final ring = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      cursor,
      9,
      ring
        ..color = Colors.black
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      cursor,
      7.5,
      ring
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      cursor,
      6,
      ring
        ..color = Colors.black
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PlanePainter old) => old.hsv != hsv;
}

/// Hue from 360° at the top down to 0° at the bottom, both ends red.
class _HueBar extends StatelessWidget {
  const _HueBar({required this.size, required this.hsv, required this.onChanged});

  final Size size;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged(hsv.withHue(360 * (1 - (p.dy / size.height).clamp(0.0, 1.0))));
    return GestureDetector(
      key: const Key('waypoint_color_picker_hue'),
      onPanDown: (d) => update(d.localPosition),
      onPanUpdate: (d) => update(d.localPosition),
      child: CustomPaint(size: size, painter: _HuePainter(hsv.hue)),
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [for (var h = 360.0; h >= 0; h -= 30) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _frame,
    );

    final y = (1 - hue / 360) * size.height;
    canvas.drawRect(Rect.fromLTRB(0, y - 2, size.width, y + 2), Paint()..color = Colors.black);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
