import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every persisted checkbox/switch in the menu panels, with its default
/// from the mockup. Values are saved by [Enum.name], so renaming a value
/// resets it to its default.
enum MenuToggle {
  settingsSk42Grid(false),
  settingsNightMode(false),
  settingsCenterCoordinates(false),
  mapsCacheOnly(false),
  mapsLoadingIndicators(false),
  mapsMapName(false),
  mapsMapScale(false),
  mapsScaleBar(false),
  waypointsNames(true),
  waypointsTargetLine(true),
  waypointsTargetStatus(true),
  positioningGeolocation(false),
  positioningRotateByMovement(false),
  positioningDistanceLine(true),
  positioningStatus(true),
  positioningRecordingStatus(true),
  orientationRotateByCompass(true),
  orientationShowCompass(false),
  orientationCompassStatus(true);

  const MenuToggle(this.defaultValue);

  final bool defaultValue;
}

abstract class MenuTogglesStore {
  Future<Map<String, bool>> load();
  Future<void> save(Map<String, bool> values);
}

/// Local-only, like the map camera and waypoint icon assignments.
class SecureMenuTogglesStore implements MenuTogglesStore {
  SecureMenuTogglesStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'menu_toggles';

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, bool>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, bool> values) => _storage.write(key: _key, value: jsonEncode(values));
}

final menuTogglesStoreProvider = Provider<MenuTogglesStore>((ref) => SecureMenuTogglesStore());

/// Starts from the defaults and applies saved values once they are read. A
/// toggle the user changes before the read finishes keeps the user's value.
class MenuTogglesController extends Notifier<Map<MenuToggle, bool>> {
  final Set<MenuToggle> _changedBeforeLoad = {};

  @override
  Map<MenuToggle, bool> build() {
    _load();
    return {for (final toggle in MenuToggle.values) toggle: toggle.defaultValue};
  }

  Future<void> _load() async {
    final Map<String, bool> saved;
    try {
      saved = await ref.read(menuTogglesStoreProvider).load();
    } catch (_) {
      return;
    }
    final next = {...state};
    for (final toggle in MenuToggle.values) {
      final value = saved[toggle.name];
      if (value != null && !_changedBeforeLoad.contains(toggle)) next[toggle] = value;
    }
    state = next;
  }

  void set(MenuToggle toggle, bool value) {
    _changedBeforeLoad.add(toggle);
    state = {...state, toggle: value};
    ref
        .read(menuTogglesStoreProvider)
        .save({for (final entry in state.entries) entry.key.name: entry.value})
        .catchError((_) {});
  }
}

final menuTogglesProvider = NotifierProvider<MenuTogglesController, Map<MenuToggle, bool>>(MenuTogglesController.new);
