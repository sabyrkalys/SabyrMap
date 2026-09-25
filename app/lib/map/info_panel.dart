import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_icons.dart';
import '../menu/menu_toggles.dart';
import '../widgets/app_icon.dart';
import 'geo_utils.dart';
import 'map_scale.dart';
import 'sk42.dart';

/// Which centre the panel shows: the live camera centre only while a
/// target exists (it is refreshed per frame then); otherwise the centre
/// the camera last settled on, so a leftover live centre can't freeze it.
LatLng infoPanelCenter({LatLng? target, LatLng? liveCenter, required LatLng settled}) =>
    target != null ? (liveCenter ?? settled) : settled;

/// Top-left overlay: centre coordinates, telemetry (recording icon, scale,
/// zoom, scale bar) and, with a «Задать цель» target, its distance and
/// azimuth. Each part follows its menu toggle; nothing shown → no block.
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.center,
    required this.zoom,
    this.target,
    required this.recording,
    required this.toggles,
  });

  final LatLng center;
  final double zoom;
  final LatLng? target;
  final bool recording;
  final Map<MenuToggle, bool> toggles;

  bool _on(MenuToggle toggle) => toggles[toggle] ?? toggle.defaultValue;

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFF16181A);
    const style = TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500);
    final lines = <Widget>[];

    if (_on(MenuToggle.settingsCenterCoordinates)) {
      final String text;
      if (_on(MenuToggle.settingsSk42Grid)) {
        final p = toSk42(center.latitude, center.longitude);
        text = 'X = ${p.x.round()} Y = ${p.y.round()}';
      } else {
        text = '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}';
      }
      lines.add(Text(text, key: const Key('info_line_coordinates'), style: style.copyWith(fontWeight: FontWeight.w700)));
    }

    final showTrack = recording && _on(MenuToggle.positioningRecordingStatus);
    final showScale = _on(MenuToggle.mapsMapScale);
    final showBar = _on(MenuToggle.mapsScaleBar);
    if (showTrack || showScale || showBar) {
      final bar = scaleBar(zoom, center.latitude);
      lines.add(
        // Wrap, not Row: with a large system font the scale, zoom and bar
        // move to the next line instead of overflowing a narrow screen.
        Wrap(
          key: const Key('info_line_telemetry'),
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (showTrack) const Icon(Icons.timeline, key: Key('info_track_icon'), size: 18, color: textColor),
            if (showScale) ...[
              Text(scaleText(zoom, center.latitude), key: const Key('info_scale_text'), style: style),
              Text(zoomText(zoom), key: const Key('info_zoom_text'), style: style),
            ],
            if (showBar)
              Column(
                key: const Key('info_scale_bar'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bar.label, style: style.copyWith(fontSize: 12)),
                  Container(
                    width: bar.widthDp,
                    height: 4,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: textColor, width: 1.5),
                        right: BorderSide(color: textColor, width: 1.5),
                        bottom: BorderSide(color: textColor, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    final target = this.target;
    if (target != null && _on(MenuToggle.waypointsTargetStatus)) {
      final meters = distanceMeters(center.latitude, center.longitude, target.latitude, target.longitude);
      final azimuth = meters == 0
          ? 0.0
          : bearingDegrees(target.latitude, target.longitude, center.latitude, center.longitude);
      lines.add(
        Row(
          key: const Key('info_line_target'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.flag, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(targetText(meters, azimuth), style: style),
          ],
        ),
      );
    }

    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('info_panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[if (i > 0) const SizedBox(height: 4), lines[i]],
        ],
      ),
    );
  }
}
