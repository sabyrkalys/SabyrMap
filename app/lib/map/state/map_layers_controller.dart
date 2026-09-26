import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../services/layer_manager.dart';

abstract class MapStateStore {
  Future<MapState?> load();
  Future<void> save(MapState state);
}

/// Local-only, like the other map settings.
class SecureMapStateStore implements MapStateStore {
  SecureMapStateStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const String storageKey = 'map_state';

  final FlutterSecureStorage _storage;

  @override
  Future<MapState?> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      return MapState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(MapState state) => _storage.write(key: storageKey, value: jsonEncode(state.toJson()));
}

final mapStateStoreProvider = Provider<MapStateStore>((ref) => SecureMapStateStore());

/// The map's layer state (base, overlays, favourites, presets).
///
/// Every change runs through the [LayerManager] first and updates the state
/// only when it succeeded, so the saved state always matches the map. A
/// refused change throws [LayerException] for the UI to show. The map screen
/// hands the manager over with [attach] once the map exists; that also puts
/// back the stack saved in the previous run.
class MapStateNotifier extends Notifier<MapState> {
  LayerManager? _manager;
  late final Future<void> _loaded;

  @override
  MapState build() {
    _loaded = _load();
    return const MapState.initial();
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(mapStateStoreProvider).load();
      if (saved != null && ref.mounted) state = saved;
    } catch (_) {}
  }

  LayerManager _requireManager() {
    final manager = _manager;
    if (manager == null) throw const LayerException('Карта ещё не готова');
    return manager;
  }

  Future<MapSource> _source(String id) async {
    final providers = await ref.read(catalogProvider.future);
    for (final provider in providers) {
      for (final source in provider.sources) {
        if (source.id == id) return source;
      }
    }
    throw LayerException('Карта «$id» не найдена в каталоге');
  }

  void _publish(MapState next) {
    state = next;
    unawaited(ref.read(mapStateStoreProvider).save(next).catchError((_) {}));
  }

  void _syncOverlays() => _publish(state.copyWith(overlays: _requireManager().getActiveLayers()));

  /// Called by the map screen when the map (and a new [manager]) exists.
  Future<LayerChangeResult> attach(LayerManager manager) async {
    _manager = manager;
    await _loaded;
    final saved = state;
    final baseId = saved.baseSourceId;
    if (baseId == null) {
      if (saved.overlays.isEmpty) return const LayerChangeResult();
      final result = await manager.restoreOverlays(saved.overlays);
      _syncOverlays();
      return result;
    }
    try {
      await manager.setBaseSource(await _source(baseId));
    } on LayerException catch (e) {
      return LayerChangeResult([e.message]);
    }
    final result = await manager.restoreOverlays(saved.overlays);
    _syncOverlays();
    return result;
  }

  Future<LayerChangeResult> setBase(MapSource source) async {
    final result = await _requireManager().setBaseSource(source);
    _publish(state.copyWith(baseSourceId: source.id, overlays: _requireManager().getActiveLayers()));
    return result;
  }

  Future<void> addOverlay(MapSource source, {double? opacity}) async {
    await _requireManager().addOverlay(source, opacity: opacity);
    _syncOverlays();
  }

  Future<void> removeOverlay(String sourceId) async {
    await _requireManager().removeOverlay(sourceId);
    _syncOverlays();
  }

  Future<void> setOpacity(String sourceId, double opacity) async {
    await _requireManager().setOpacity(sourceId, opacity);
    _syncOverlays();
  }

  Future<void> setVisibility(String sourceId, bool visible) async {
    await _requireManager().setVisibility(sourceId, visible);
    _syncOverlays();
  }

  Future<void> reorderOverlays(List<String> orderedIds) async {
    await _requireManager().reorderOverlays(orderedIds);
    _syncOverlays();
  }

  Future<void> toggleFavorite(String sourceId) async {
    final favorites = List.of(state.favoriteIds);
    favorites.contains(sourceId) ? favorites.remove(sourceId) : favorites.add(sourceId);
    _publish(state.copyWith(favoriteIds: favorites));
  }

  /// Switches to [preset]'s base and replaces the overlays with its own.
  Future<LayerChangeResult> applyPreset(MapPreset preset) async {
    final manager = _requireManager();
    final base = await _source(preset.baseSourceId);
    // Problems restoring the old overlays don't matter: they are replaced by
    // the preset's own right away.
    await manager.setBaseSource(base);
    for (final layer in manager.getActiveLayers()) {
      await manager.removeOverlay(layer.sourceId);
    }
    final result = await manager.restoreOverlays(preset.overlays);
    _publish(state.copyWith(baseSourceId: base.id, overlays: manager.getActiveLayers()));
    return result;
  }

  /// Stores the current base + overlays as a preset named [name].
  Future<void> savePreset(String name) async {
    final base = state.baseSourceId;
    if (base == null) throw const LayerException('Сначала выберите карту');
    final preset = MapPreset(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      baseSourceId: base,
      overlays: state.overlays,
    );
    _publish(state.copyWith(presets: [...state.presets, preset]));
  }

  Future<void> deletePreset(String id) async =>
      _publish(state.copyWith(presets: [for (final p in state.presets) if (p.id != id) p]));
}

final mapLayersProvider = NotifierProvider<MapStateNotifier, MapState>(MapStateNotifier.new);
