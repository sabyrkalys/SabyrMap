import 'package:app/icons/waypoint_icon_store.dart';

class FakeWaypointIconStore implements WaypointIconStore {
  final Map<String, String> icons = {};

  @override
  Future<String?> iconFor(String waypointId) async => icons[waypointId];

  @override
  Future<void> setIcon(String waypointId, String? fileName) async {
    if (fileName == null) {
      icons.remove(waypointId);
    } else {
      icons[waypointId] = fileName;
    }
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(icons);
}
