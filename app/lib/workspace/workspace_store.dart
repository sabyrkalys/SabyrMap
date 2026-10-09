import 'dart:convert';

import 'package:app/app_settings/app_settings_keys.dart';
import 'package:app/landmarks/settings/app_settings.dart';

import 'workspace.dart';
import 'workspace_snapshot.dart';
import 'workspace_state.dart';

/// Пространства и их снимки в настройках: `workspace.list` (JSON),
/// `workspace.active`, `workspace.snapshot.<id>` (JSON).
class WorkspaceStore {
  WorkspaceStore(this._settings);

  final AppSettings _settings;

  /// Список и активное; нет записи или она повреждена — пусто.
  Future<WorkspaceState> load() async {
    final raw = _settings.getString(AppSettingsKeys.workspaceList);
    var list = <Workspace>[];
    if (raw != null) {
      try {
        list = [for (final e in jsonDecode(raw) as List<dynamic>) Workspace.fromJson(e as Map<String, dynamic>)];
      } on Object {
        list = [];
      }
    }
    final active = _settings.getString(AppSettingsKeys.workspaceActive);
    return WorkspaceState(workspaces: List.unmodifiable(list), activeId: list.any((w) => w.id == active) ? active : null);
  }

  Future<void> saveList(List<Workspace> ws, String? activeId) async {
    await _settings.setString(AppSettingsKeys.workspaceList, jsonEncode([for (final w in ws) w.toJson()]));
    if (activeId == null) {
      await _settings.remove(AppSettingsKeys.workspaceActive);
    } else {
      await _settings.setString(AppSettingsKeys.workspaceActive, activeId);
    }
  }

  Future<WorkspaceSnapshot?> loadSnapshot(String id) async {
    final raw = _settings.getString(_key(id));
    if (raw == null) return null;
    try {
      return WorkspaceSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<void> saveSnapshot(String id, WorkspaceSnapshot snap) => _settings.setString(_key(id), jsonEncode(snap.toJson()));

  Future<void> deleteSnapshot(String id) => _settings.remove(_key(id));

  static String _key(String id) => '${AppSettingsKeys.workspaceSnapshotPrefix}$id';
}
