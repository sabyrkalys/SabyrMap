import 'package:flutter/material.dart';

/// Parses a `#RRGGBB` hex string (as used throughout the waypoints API and
/// [waypointTypeColors]) into an opaque [Color].
Color colorFromHex(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}

/// Formats an opaque [Color] back into a `#RRGGBB` hex string, discarding
/// alpha (waypoint colors are always fully opaque).
String colorToHex(Color color) {
  String twoDigits(int channel) => channel.toRadixString(16).padLeft(2, '0').toUpperCase();
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${twoDigits(r)}${twoDigits(g)}${twoDigits(b)}';
}
