import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';

import 'favorite_set.dart';

/// Избранные наборы в настройках: JSON-массив под `maps.favorite_sets`.
class FavoriteSetStore {
  FavoriteSetStore(this._settings);

  final AppSettings _settings;

  /// Все наборы; нет записи или она повреждена — пусто.
  Future<List<FavoriteSet>> loadAll() async {
    final raw = _settings.getString(SettingsKeys.mapsFavoriteSets);
    if (raw == null) return const [];
    try {
      return [for (final e in jsonDecode(raw) as List<dynamic>) FavoriteSet.fromJson(e as Map<String, dynamic>)];
    } on Object {
      return const [];
    }
  }

  /// Сохраняет набор (тот же id заменяется на месте).
  Future<void> save(FavoriteSet set) async {
    final all = await loadAll();
    final i = all.indexWhere((s) => s.id == set.id);
    await _write(i < 0 ? [...all, set] : ([...all]..[i] = set));
  }

  Future<void> remove(String id) async => _write([...(await loadAll()).where((s) => s.id != id)]);

  Future<FavoriteSet?> byId(String id) async => (await loadAll()).where((s) => s.id == id).firstOrNull;

  Future<void> _write(List<FavoriteSet> sets) =>
      _settings.setString(SettingsKeys.mapsFavoriteSets, jsonEncode([for (final s in sets) s.toJson()]));
}
