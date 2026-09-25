import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'geo_utils.dart';
import 'map_target.dart';

/// Colour of the «Задать цель» line and distance label.
const Color targetColor = Color(0xFFFF8C00);
const String targetLineColorHex = '#FF8C00';

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

/// Orange distance from the crosshair to the target, shown above the crosshair.
class TargetDistanceLabel extends StatelessWidget {
  const TargetDistanceLabel({super.key, required this.from, required this.to});

  final LatLng from;
  final LatLng to;

  @override
  Widget build(BuildContext context) {
    final meters = distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude);
    return Text(
      formatDistance(meters),
      style: const TextStyle(
        color: targetColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        shadows: [Shadow(color: Colors.white, blurRadius: 3)],
      ),
    );
  }
}
