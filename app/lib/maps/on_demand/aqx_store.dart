import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';

import 'aqx_descriptor.dart';

/// Описания онлайн-карт в настройках: JSON-массив под `maps.aqx_descriptors`.
class AqxStore {
  AqxStore(this._settings);

  final AppSettings _settings;

  Future<List<AqxDescriptor>> loadAll() async {
    final raw = _settings.getString(SettingsKeys.mapsAqxDescriptors);
    if (raw == null) return const [];
    try {
      return [for (final e in jsonDecode(raw) as List<dynamic>) AqxDescriptor.fromJson(e as Map<String, dynamic>)];
    } on Object {
      return const [];
    }
  }

  /// Сохраняет описание (тот же id заменяется).
  Future<void> save(AqxDescriptor descriptor) async {
    final all = await loadAll();
    final i = all.indexWhere((d) => d.id == descriptor.id);
    await _write(i < 0 ? [...all, descriptor] : ([...all]..[i] = descriptor));
  }

  Future<void> remove(String id) async => _write([...(await loadAll()).where((d) => d.id != id)]);

  Future<AqxDescriptor?> byId(String id) async => (await loadAll()).where((d) => d.id == id).firstOrNull;

  Future<void> _write(List<AqxDescriptor> all) =>
      _settings.setString(SettingsKeys.mapsAqxDescriptors, jsonEncode([for (final d in all) d.toJson()]));
}
