import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/foundation.dart';
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

/// Значок из библиотеки — в самом файле точки (`user_icon`): не теряется
/// при переименовании и переносе. Читается из индекса меток, пишется через
/// [LandmarkServices.patchMetadata]. У объекта внутри файла меток значок
/// не меняется (он только для показа).
class FileWaypointIconStore implements WaypointIconStore {
  FileWaypointIconStore(this._services);

  final LandmarkServices _services;

  /// Индекс меток: значки меняются вместе с ним.
  Listenable get changes => _services.index;

  @override
  Future<String?> iconFor(String waypointId) async => _services.index.byPath(waypointId)?.userIcon;

  @override
  Future<void> setIcon(String waypointId, String? fileName) async {
    if (LandmarkItem.fileOf(waypointId) != waypointId) return;
    if (await iconFor(waypointId) == fileName) return;
    await _services.patchMetadata(waypointId, MetadataPatch(set: {LandmarkMetadata.userIconKey: fileName}));
  }

  @override
  Future<Map<String, String>> readAll() async => {
    for (final item in _services.index.items)
      if (item.userIcon case final icon?) item.path: icon,
  };
}
