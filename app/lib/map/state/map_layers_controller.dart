import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../base/world_base_map.dart';
import '../catalog/catalog_repository.dart';
import '../models/layer_look.dart';
import '../models/map_models.dart';
import '../orthophoto/orthophoto_extent.dart';
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
  /// Key of all orthophotos together in [layerLooksProvider] and preset looks.
  static const String orthophotosKey = '@orthophotos';

  /// The built-in world map under every map («Базовая карта»).
  static const String worldKey = '@world';

  /// The chosen map («Карта») in [layerLooksProvider] and preset looks.
  static const String mapKey = '@map';

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

  /// Raster overlay limit of the attached manager.
  int get maxOverlays => _manager?.maxRasterOverlays ?? 3;

  LayerManager _requireManager() {
    final manager = _manager;
    if (manager == null) throw const LayerException('Карта ещё не готова');
    return manager;
  }

  Future<MapSource> _source(String id) async {
    if (id == LayerManager.noMapId) return LayerManager.noMap;
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
    ref.read(layerLooksProvider.notifier).retain({for (final l in next.overlays) l.sourceId});
    unawaited(ref.read(mapStateStoreProvider).save(next).catchError((_) {}));
  }

  void _syncOverlays() => _publish(state.copyWith(overlays: _requireManager().getActiveLayers()));

  /// Called by the map screen when the map (and a new [manager]) exists.
  Future<LayerChangeResult> attach(LayerManager manager) async {
    _manager = manager;
    await _loaded;
    final saved = state;
    // No base chosen yet, or the saved one left the catalog (renamed server
    // maps, a deleted local file) → start on the default (our map server).
    var baseId = saved.baseSourceId ?? CatalogRepository.defaultBaseSourceId;
    // Встроенная карта мира ложится под каждую карту при смене стиля; её
    // копирование из APK не задерживает показ карты.
    unawaited(_attachWorld(manager));
    await manager.setMapVisible(state.mapVisible);
    try {
      MapSource base;
      try {
        base = await _source(baseId);
      } on LayerException {
        if (baseId == CatalogRepository.defaultBaseSourceId) rethrow;
        baseId = CatalogRepository.defaultBaseSourceId;
        base = await _source(baseId);
      }
      await manager.setBaseSource(base);
      if (saved.baseSourceId != baseId) state = state.copyWith(baseSourceId: baseId);
      if (state.mapOpacity != 1) await manager.setMapPaint(opacity: state.mapOpacity);
    } on LayerException catch (e) {
      return LayerChangeResult([e.message]);
    }
    // Orthophotos added as overlays by earlier versions now belong to the
    // orthophoto switch.
    final orthophotoIds = {for (final s in await _orthophotoSources()) s.id};
    final overlays = [for (final l in saved.overlays) if (!orthophotoIds.contains(l.sourceId)) l];
    if (overlays.length != saved.overlays.length) state = state.copyWith(orthophotosOn: true);
    await manager.setOrthophotoPaint(opacity: state.orthophotoOpacity);
    final result = await manager.restoreOverlays(overlays);
    _syncOverlays();
    // Orthophotos (when on) come with the first [updateOrthophotos]: only the
    // ones around the screen are put on the map.
    return result;
  }

  Future<void> _attachWorld(LayerManager manager) async {
    try {
      final path = await ref.read(worldBaseMapPathProvider.future);
      if (ref.mounted && identical(_manager, manager)) await manager.setWorld(path, opacity: state.worldOpacity);
    } catch (_) {}
  }

  /// Orthophotos of the catalog (mediafile/orthophoto).
  Future<List<MapSource>> _orthophotoSources() async {
    final providers = await ref.read(catalogProvider.future);
    return [
      for (final provider in providers)
        if (provider.id == CatalogRepository.orthophotoProviderId) ...provider.sources,
    ];
  }

  /// Turns orthophotos on or off; remembered. Turning on re-reads the
  /// folder (new territories dropped in) and returns how many files there
  /// are; the map then calls [updateOrthophotos] for the screen.
  Future<int> setOrthophotosOn(bool on) async {
    _publish(state.copyWith(orthophotosOn: on));
    if (!on) {
      await _manager?.setOrthophotos(const []);
      return 0;
    }
    await ref.read(catalogProvider.notifier).reload();
    return (await _orthophotoSources()).length;
  }

  /// Opacity of all orthophotos while a slider is dragged;
  /// [setOrthophotoOpacity] stores the final value.
  Future<void> previewOrthophotoOpacity(double opacity) async =>
      _manager?.setOrthophotoPaint(opacity: opacity);

  /// Shows or hides the chosen map; remembered.
  Future<void> setMapVisible(bool visible) async {
    await _manager?.setMapVisible(visible);
    _publish(state.copyWith(mapVisible: visible));
  }

  /// Opacity of the world map while a slider is dragged; [setWorldOpacity]
  /// stores the final value.
  Future<void> previewWorldOpacity(double opacity) async => _manager?.setWorldOpacity(opacity);

  Future<void> setWorldOpacity(double opacity) async {
    await _manager?.setWorldOpacity(opacity);
    _publish(state.copyWith(worldOpacity: opacity.clamp(0.0, 1.0)));
  }

  Future<void> setOrthophotoOpacity(double opacity) async {
    await _manager?.setOrthophotoPaint(opacity: opacity);
    _publish(state.copyWith(orthophotoOpacity: opacity.clamp(0.0, 1.0)));
  }

  /// Puts on the map the orthophotos around [viewport] (the screen and its
  /// neighbours) and takes off the rest; nothing when orthophotos are off.
  Future<LayerChangeResult> updateOrthophotos(GeoBox viewport, double zoom) async {
    final manager = _manager;
    if (!state.orthophotosOn || manager == null) return const LayerChangeResult();
    final sources = await _orthophotoSources();
    final reader = ref.read(mbtilesExtentReaderProvider);
    final extents = <String, MbtilesExtent?>{
      for (final source in sources)
        source.id: switch (orthophotoPath(source)) {
          final path? => await reader.read(path),
          null => null,
        },
    };
    return manager.setOrthophotos(orthophotosFor(sources, extents, viewport: viewport, zoom: zoom));
  }

  /// Another map than the current one starts with full opacity and no look.
  Future<LayerChangeResult> setBase(MapSource source) async {
    final changed = source.id != state.baseSourceId;
    final result = await _requireManager().setBaseSource(source);
    if (changed) ref.read(layerLooksProvider.notifier).put(mapKey, const LayerLook());
    _publish(state.copyWith(
      baseSourceId: source.id,
      overlays: _requireManager().getActiveLayers(),
      mapOpacity: changed ? 1.0 : state.mapOpacity,
    ));
    return result;
  }

  /// Opacity of the chosen map while a slider is dragged; [setMapOpacity]
  /// stores the final value.
  Future<void> previewMapOpacity(double opacity) async => _manager?.setMapPaint(opacity: opacity);

  Future<void> setMapOpacity(double opacity) async {
    await _manager?.setMapPaint(opacity: opacity);
    _publish(state.copyWith(mapOpacity: opacity.clamp(0.0, 1.0)));
  }

  /// Убирает выбранную карту: остаются базовая карта, слои и ортофотопланы.
  Future<LayerChangeResult> removeMap() => setBase(LayerManager.noMap);

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

  /// Changes the map's opacity while a slider is dragged; [setOpacity]
  /// stores the final value.
  Future<void> previewOpacity(String sourceId, double opacity) => _requireManager().setOpacity(sourceId, opacity);

  /// Shows or hides an overlay on the map only, without storing it (the
  /// compare mode puts the stored visibility back on exit).
  Future<void> previewVisibility(String sourceId, bool visible) => _requireManager().setVisibility(sourceId, visible);

  /// Session look of [sourceId] ([LayerLook]); the colour goes to the map.
  Future<void> setLook(String sourceId, LayerLook look) async {
    final looks = ref.read(layerLooksProvider.notifier);
    final before = looks.of(sourceId);
    looks.put(sourceId, look);
    if (before.color == look.color) return;
    switch (sourceId) {
      case orthophotosKey:
        await _requireManager().setOrthophotoPaint(color: look.color);
      case mapKey:
        await _requireManager().setMapPaint(color: look.color);
      default:
        await _requireManager().setColor(sourceId, look.color);
    }
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
    await manager.setOrthophotoPaint(color: (preset.looks[orthophotosKey] ?? const LayerLook()).color);
    await manager.setMapPaint(opacity: 1, color: (preset.looks[mapKey] ?? const LayerLook()).color);
    for (final entry in preset.looks.entries) {
      if (entry.key != orthophotosKey && entry.key != mapKey) await manager.setColor(entry.key, entry.value.color);
    }
    final result = await manager.restoreOverlays(preset.overlays);
    ref.read(layerLooksProvider.notifier).replaceAll(preset.looks);
    _publish(state.copyWith(baseSourceId: base.id, overlays: manager.getActiveLayers(), mapOpacity: 1.0));
    return result;
  }

  /// Stores the current base + overlays (with their looks) as a preset
  /// named [name].
  Future<void> savePreset(String name) async {
    final base = state.baseSourceId;
    if (base == null) throw const LayerException('Сначала выберите карту');
    final preset = MapPreset(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      baseSourceId: base,
      overlays: state.overlays,
      looks: {
        for (final e in ref.read(layerLooksProvider).entries)
          if (!e.value.copyWith(forceRefresh: false).isDefault) e.key: e.value.copyWith(forceRefresh: false),
      },
    );
    _publish(state.copyWith(presets: [...state.presets, preset]));
  }

  Future<void> renamePreset(String id, String name) async => _publish(state.copyWith(presets: [
        for (final p in state.presets) p.id == id ? p.copyWith(name: name) : p,
      ]));

  Future<void> deletePreset(String id) async =>
      _publish(state.copyWith(presets: [for (final p in state.presets) if (p.id != id) p]));
}

final mapLayersProvider = NotifierProvider<MapStateNotifier, MapState>(MapStateNotifier.new);

/// Session looks of the overlays on the map, by source id. Not saved:
/// a look leaves with its overlay and comes back only with a favourite set.
class LayerLooksNotifier extends Notifier<Map<String, LayerLook>> {
  @override
  Map<String, LayerLook> build() => const {};

  LayerLook of(String sourceId) => state[sourceId] ?? const LayerLook();

  void put(String sourceId, LayerLook look) {
    final next = Map.of(state);
    look.isDefault ? next.remove(sourceId) : next[sourceId] = look;
    state = next;
  }

  void replaceAll(Map<String, LayerLook> looks) => state = Map.unmodifiable(looks);

  /// Drops the looks of overlays no longer on the map; the orthophotos'
  /// look always stays.
  void retain(Set<String> sourceIds) {
    bool keep(String id) =>
        id == MapStateNotifier.orthophotosKey || id == MapStateNotifier.mapKey || sourceIds.contains(id);
    if (state.keys.every(keep)) return;
    state = {for (final e in state.entries) if (keep(e.key)) e.key: e.value};
  }
}

final layerLooksProvider = NotifierProvider<LayerLooksNotifier, Map<String, LayerLook>>(LayerLooksNotifier.new);
