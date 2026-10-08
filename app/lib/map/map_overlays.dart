import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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
        _RoundButton(key: const Key('zoom_in_button'), icon: Icons.add, onTap: onZoomIn),
        const SizedBox(height: 12),
        _RoundButton(key: const Key('zoom_out_button'), icon: Icons.remove, onTap: onZoomOut),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.onTap});

  static const double _size = 48;

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Icon(icon, color: const Color(0xFF16181A)),
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
