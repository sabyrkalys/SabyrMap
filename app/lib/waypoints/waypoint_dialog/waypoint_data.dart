import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../waypoint_color.dart';
import '../waypoint_types.dart';
import 'marker_group.dart';

/// What the «Путевая точка» dialog returns on «ОК».
class WaypointData {
  const WaypointData({
    this.name = '',
    this.point,
    this.groupId = unsortedGroupId,
    this.iconId,
    this.markerIconId,
    this.colorValue,
    this.type = defaultWaypointType,
    this.note = '',
  });

  /// «Несортированные метки», where waypoints go by default.
  static const unsortedGroupId = MarkerGroup.unsortedId;

  /// May be empty: the waypoint is then named «Путевая точка N».
  final String name;

  /// Coordinates typed in «Координаты»; null puts the waypoint at the
  /// crosshair (or the target) as usual.
  final LatLng? point;
  final String groupId;

  /// File name of the chosen icon file; null keeps the standard marker.
  final String? iconId;

  /// A built-in icon from «Иконка» (MarkerIcon.id). Not drawn on the map
  /// yet: that comes with the real icon set.
  final String? markerIconId;

  /// ARGB of the chosen colour; null keeps the type's colour.
  final int? colorValue;
  final String type;
  final String note;

  /// [colorValue] as the API's `#RRGGBB`.
  String? get colorHex => colorValue == null ? null : colorToHex(Color(colorValue!));
}

/// «Путевая точка N» with N one past the highest N among [existingNames],
/// so unnamed waypoints are numbered in order.
String nextWaypointName(Iterable<String> existingNames) {
  final pattern = RegExp(r'^Путевая точка (\d+)$');
  var highest = 0;
  for (final name in existingNames) {
    final match = pattern.firstMatch(name.trim());
    if (match == null) continue;
    final n = int.parse(match.group(1)!);
    if (n > highest) highest = n;
  }
  return 'Путевая точка ${highest + 1}';
}
