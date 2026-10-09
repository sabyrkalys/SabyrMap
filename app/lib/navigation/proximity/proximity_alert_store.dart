import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';

import 'proximity_alert.dart';
import 'proximity_zone.dart';

/// Оповещения рабочего пространства в настройках: JSON-массив под ключом
/// `navigation.proximity.<workspaceId>`.
class ProximityAlertStore {
  ProximityAlertStore(this._settings);

  final AppSettings _settings;

  static String key(String workspaceId) => '${SettingsKeys.proximityPrefix}$workspaceId';

  /// Decision: зоны хранятся рядом (`<key>.zones`), чтобы после перезапуска
  /// не сигналить заново «вошли в зону», если положение не изменилось.
  static String zonesKey(String workspaceId) => '${key(workspaceId)}.zones';

  /// Оповещения; нет записи или она повреждена — пусто.
  Future<List<ProximityAlert>> load(String workspaceId) async {
    final raw = _settings.getString(key(workspaceId));
    if (raw == null) return const [];
    try {
      return [for (final item in jsonDecode(raw) as List<dynamic>) ProximityAlert.fromJson(item as Map<String, dynamic>)];
    } on Object {
      return const [];
    }
  }

  Future<void> save(String workspaceId, List<ProximityAlert> alerts) =>
      _settings.setString(key(workspaceId), jsonEncode([for (final a in alerts) a.toJson()]));

  Future<void> add(String workspaceId, ProximityAlert alert) async =>
      save(workspaceId, [...(await load(workspaceId)).where((a) => a.id != alert.id), alert]);

  Future<void> remove(String workspaceId, String alertId) async =>
      save(workspaceId, [...(await load(workspaceId)).where((a) => a.id != alertId)]);

  /// Заменяет оповещение с тем же id; нет такого — добавляет.
  Future<void> update(String workspaceId, ProximityAlert alert) async {
    final alerts = await load(workspaceId);
    final index = alerts.indexWhere((a) => a.id == alert.id);
    await save(workspaceId, index < 0 ? [...alerts, alert] : ([...alerts]..[index] = alert));
  }

  Future<Map<String, ProximityZone>> loadZones(String workspaceId) async {
    final raw = _settings.getString(zonesKey(workspaceId));
    if (raw == null) return const {};
    try {
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (ProximityZone.values.where((z) => z.name == value).firstOrNull case final zone?) key: zone,
      };
    } on Object {
      return const {};
    }
  }

  Future<void> saveZones(String workspaceId, Map<String, ProximityZone> zones) =>
      _settings.setString(zonesKey(workspaceId), jsonEncode({for (final e in zones.entries) e.key: e.value.name}));
}
