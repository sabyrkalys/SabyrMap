import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_icons.dart';
import '../geo/sun_times.dart';
import '../geo/wmm.dart';
import '../menu/menu_widgets.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';
import 'sk42.dart';

/// «8.1° В» / «0.6° З»; a value that rounds to zero is «0.0°».
String formatAngleEw(double degrees) {
  final text = degrees.abs().toStringAsFixed(1);
  if (text == '0.0') return '0.0°';
  return '$text° ${degrees > 0 ? 'В' : 'З'}';
}

/// «UTC+3», «UTC+5:30», «UTC−3:30», «UTC+0».
String formatUtcOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '−' : '+';
  final abs = minutes.abs();
  final hours = abs ~/ 60;
  final rest = abs % 60;
  return rest == 0 ? 'UTC$sign$hours' : 'UTC$sign$hours:${rest.toString().padLeft(2, '0')}';
}

/// «05:03» in the given (local) time; «—» when there is no event.
String formatClock(DateTime? local) {
  if (local == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

Future<void> showPointInfoSheet(BuildContext context, {required LatLng point, required bool sk42}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PointInfoSheet(point: point, sk42: sk42, now: DateTime.now()),
  );
}

/// ИНФОРМАЦИЯ: details about one point (the spot under the crosshair).
class PointInfoSheet extends StatelessWidget {
  const PointInfoSheet({super.key, required this.point, required this.sk42, required this.now});

  final LatLng point;
  final bool sk42;

  /// Local "now" of the phone; its date picks the day for sunrise/sunset,
  /// its offset is the time zone shown.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final lat = point.latitude;
    final lng = point.longitude;
    final String coordinates;
    if (sk42) {
      final p = toSk42(lat, lng);
      coordinates = 'X = ${p.x.round()} Y = ${p.y.round()}';
    } else {
      coordinates = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    final declination = magneticDeclination(lat, lng, decimalYear: decimalYear(now.toUtc()));
    final convergence = sk42Convergence(lat, lng);
    final sun = sunTimes(lat, lng, now);
    final offset = now.timeZoneOffset;
    DateTime? local(DateTime? utc) => utc?.add(offset);

    final labelStyle = AppTextStyles.menuItemDisabled(context).copyWith(fontSize: 14);
    final valueStyle = AppTextStyles.menuItem(context);
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      // Both sides flex so a long value (СК-42) or a large system font
      // wraps instead of overflowing a narrow screen.
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
    Widget text(String value, [Key? key]) => Text(value, key: key, style: valueStyle, textAlign: TextAlign.end);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: MenuPanel.background,
          child: SafeArea(
            top: false,
            // Scrolls when a landscape phone or a large font makes it taller
            // than the screen.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('ИНФОРМАЦИЯ', style: AppTextStyles.sectionHeader(context)),
                  ),
                  row('Координаты', text(coordinates, const Key('point_info_coordinates'))),
                  row('Склонение (магнитное)', text(formatAngleEw(declination), const Key('point_info_declination'))),
                  row('Конвергенция меридианов', text(formatAngleEw(convergence), const Key('point_info_convergence'))),
                  row(
                    'Время восхода и заката',
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppIcon(
                          AppIcons.sunrise,
                          key: const Key('point_info_sunrise_icon'),
                          size: 20,
                          color: valueStyle.color,
                        ),
                        const SizedBox(width: 4),
                        text(formatClock(local(sun.sunrise))),
                        const SizedBox(width: 12),
                        AppIcon(
                          AppIcons.sunset,
                          key: const Key('point_info_sunset_icon'),
                          size: 20,
                          color: valueStyle.color,
                        ),
                        const SizedBox(width: 4),
                        text(formatClock(local(sun.sunset))),
                      ],
                    ),
                  ),
                  row('Часовой пояс', text(formatUtcOffset(offset))),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
