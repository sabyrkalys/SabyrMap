import 'package:flutter/painting.dart';

import '../waypoint_color.dart';
import '../waypoint_types.dart';

/// Where the new waypoint goes.
enum WaypointCoords {
  /// The crosshair (or the «Задать цель» target the dialog was opened for).
  screenCenter,

  /// A point the user taps on the map after «ОК».
  customPoint,
}

/// What the «Путевая точка» dialog returns on «ОК».
class WaypointData {
  const WaypointData({
    this.name = '',
    this.coords = WaypointCoords.screenCenter,
    this.groupId = unsortedGroupId,
    this.iconId,
    this.colorValue,
    this.type = defaultWaypointType,
    this.note = '',
  });

  /// The one group there is so far: «Несортированные метки».
  static const unsortedGroupId = 'unsorted';

  /// May be empty: the waypoint is then named «Путевая точка N».
  final String name;
  final WaypointCoords coords;
  final String groupId;

  /// File name of the chosen icon; null keeps the standard marker.
  final String? iconId;

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
