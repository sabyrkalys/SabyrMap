import 'dart:convert';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:app/maps/color/color_range.dart';
import 'package:app/maps/dem/dem_settings.dart';

/// Настройки карт поверх [AppSettings] (значения хранятся строками).
class MapsSettings {
  MapsSettings(this._settings);

  final AppSettings _settings;

  static const int defaultKeepCacheDays = 30;

  AppSettings get raw => _settings;

  bool get useOnlyLocalStorage => _bool(SettingsKeys.mapsUseOnlyLocalStorage, false);
  Future<void> setUseOnlyLocalStorage(bool v) => _settings.setString(SettingsKeys.mapsUseOnlyLocalStorage, '$v');

  bool get showLocalCoverage => _bool(SettingsKeys.mapsShowLocalCoverage, false);
  Future<void> setShowLocalCoverage(bool v) => _settings.setString(SettingsKeys.mapsShowLocalCoverage, '$v');

  bool get autoDownloadElevation => _bool(SettingsKeys.mapsAutoDownloadElevation, false);
  Future<void> setAutoDownloadElevation(bool v) => _settings.setString(SettingsKeys.mapsAutoDownloadElevation, '$v');

  bool get informationBox => _bool(SettingsKeys.mapsInformationBox, true);
  Future<void> setInformationBox(bool v) => _settings.setString(SettingsKeys.mapsInformationBox, '$v');

  /// Ширина диапазона стирания цвета, 1..255; по умолчанию 5.
  int get colorRangesWidth {
    final v = int.tryParse(_settings.getString(SettingsKeys.mapsColorRangesWidth) ?? '');
    return v != null && v >= 1 && v <= 255 ? v : ColorRange.defaultWidth;
  }

  Future<void> setColorRangesWidth(int v) {
    if (v < 1 || v > 255) throw ArgumentError.value(v, 'v', 'must be within 1..255');
    return _settings.setString(SettingsKeys.mapsColorRangesWidth, '$v');
  }

  DemSettings get demSettings {
    final raw = _settings.getString(SettingsKeys.mapsDemSettings);
    if (raw == null) return const DemSettings();
    try {
      return DemSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const DemSettings();
    }
  }

  Future<void> setDemSettings(DemSettings v) => _settings.setString(SettingsKeys.mapsDemSettings, jsonEncode(v.toJson()));

  String? get currentSource => _settings.getString(SettingsKeys.mapsCurrentSource);
  Future<void> setCurrentSource(String? id) => id == null
      ? _settings.remove(SettingsKeys.mapsCurrentSource)
      : _settings.setString(SettingsKeys.mapsCurrentSource, id);

  int get keepCacheDays {
    final v = int.tryParse(_settings.getString(SettingsKeys.mapsOfflineKeepCacheDays) ?? '');
    return v != null && v >= 0 ? v : defaultKeepCacheDays;
  }

  Future<void> setKeepCacheDays(int v) {
    if (v < 0) throw ArgumentError.value(v, 'v', 'must not be negative');
    return _settings.setString(SettingsKeys.mapsOfflineKeepCacheDays, '$v');
  }

  /// Стек слоёв, JSON (читает [LayerStackController]).
  String? get layerStackJson => _settings.getString(SettingsKeys.mapsLayerStack);
  Future<void> setLayerStackJson(String json) => _settings.setString(SettingsKeys.mapsLayerStack, json);

  bool _bool(String key, bool fallback) => switch (_settings.getString(key)) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}
