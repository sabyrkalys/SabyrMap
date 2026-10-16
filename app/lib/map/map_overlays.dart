import 'package:app/landmarks/models/landmark_location.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'drawing/set_panel.dart';
import 'geo_utils.dart';
import 'map_scale.dart';

/// Colour of the «Задать цель» distance plate; the line and dot are drawn
/// natively in the same colour (TargetLine.kt).
const Color targetColor = Color(0xFFE0218A);

/// Round «+» / «−» buttons stacked vertically, bottom-right over the map.
class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({super.key, required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapRoundButton(
          key: const Key('zoom_in_button'),
          onTap: onZoomIn,
          child: const Icon(Icons.add, color: MapRoundButton.iconColor),
        ),
        const SizedBox(height: 12),
        MapRoundButton(
          key: const Key('zoom_out_button'),
          onTap: onZoomOut,
          child: const Icon(Icons.remove, color: MapRoundButton.iconColor),
        ),
      ],
    );
  }
}

/// Round button over the map (zoom, orthophotos): 48 dp, shadow. White;
/// with [active] (a switch that is on) — filled teal, for a white icon.
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({super.key, required this.child, required this.onTap, this.tooltip, this.active = false});

  static const double _size = 48;
  static const Color iconColor = Color(0xFF16181A);
  static const Color activeColor = Color(0xFF00897B);

  /// Icon colour for [active].
  static Color iconColorFor(bool active) => active ? Colors.white : iconColor;

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? activeColor : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          triggerMode: tooltip == null ? TooltipTriggerMode.manual : TooltipTriggerMode.longPress,
          child: SizedBox(width: _size, height: _size, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Plate with the distance from the crosshair to the target, «36,64 км»;
/// the map screen puts it right of the crosshair.
class TargetDistanceLabel extends StatelessWidget {
  const TargetDistanceLabel({super.key, required this.from, required this.to});

  final LatLng from;
  final LatLng to;

  @override
  Widget build(BuildContext context) {
    final meters = distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: targetColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          formatTargetDistance(meters),
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Расстояние и азимут от последней точки рисуемого маршрута до прицела:
/// «285 м» над «150.1°», цветом цели, в белой обводке — без плашки, чтобы
/// не закрывать карту.
class DrawingLegLabel extends StatelessWidget {
  const DrawingLegLabel({super.key, required this.from, required this.to});

  final LandmarkLocation from;
  final LatLng to;

  static const TextStyle _style = TextStyle(
    color: targetColor,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.15,
    shadows: [
      Shadow(color: Colors.white, blurRadius: 2),
      Shadow(color: Colors.white, blurRadius: 4),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final meters = distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude);
    final azimuth = bearingDegrees(from.latitude, from.longitude, to.latitude, to.longitude);
    return Text(
      '${SetPanel.formatLength(meters)}\n${azimuth.toStringAsFixed(1)}°',
      textAlign: TextAlign.center,
      style: _style,
    );
  }
}
