import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class WaypointIconStore {
  Future<String?> iconFor(String waypointId);
  Future<void> setIcon(String waypointId, String? fileName);
  Future<Map<String, String>> readAll();
}

/// Persists which local icon file (if any) is assigned to each waypoint id.
/// Local-only by design: never sent to the backend, never read from it --
/// see docs/superpowers/specs/2026-09-15-waypoint-custom-icons-design.md.
class SecureWaypointIconStore implements WaypointIconStore {
  SecureWaypointIconStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'waypoint_icon_';

  final FlutterSecureStorage _storage;

  String _keyFor(String waypointId) => '$_prefix$waypointId';

  @override
  Future<String?> iconFor(String waypointId) => _storage.read(key: _keyFor(waypointId));

  @override
  Future<void> setIcon(String waypointId, String? fileName) {
    final key = _keyFor(waypointId);
    if (fileName == null) return _storage.delete(key: key);
    return _storage.write(key: key, value: fileName);
  }

  @override
  Future<Map<String, String>> readAll() async {
    final all = await _storage.readAll();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith(_prefix)) entry.key.substring(_prefix.length): entry.value,
    };
  }
}

final waypointIconStoreProvider = Provider<WaypointIconStore>((ref) => SecureWaypointIconStore());
