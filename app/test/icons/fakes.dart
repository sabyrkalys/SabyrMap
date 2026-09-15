import 'package:app/icons/waypoint_icon_store.dart';

class FakeWaypointIconStore implements WaypointIconStore {
  final Map<String, String> icons = {};

  /// When set, [setIcon] throws this instead of writing.
  Object? setIconError;

  @override
  Future<String?> iconFor(String waypointId) async => icons[waypointId];

  @override
  Future<void> setIcon(String waypointId, String? fileName) async {
    if (setIconError != null) {
      throw setIconError!;
    }
    if (fileName == null) {
      icons.remove(waypointId);
    } else {
      icons[waypointId] = fileName;
    }
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(icons);
}
