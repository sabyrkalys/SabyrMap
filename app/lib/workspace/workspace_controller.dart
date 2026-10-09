import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/maps/layer_stack/layer_stack_controller.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:app/navigation/proximity/proximity_alert_controller.dart';
import 'package:app/navigation/settings/navigation_settings.dart';
import 'package:app/navigation/target/target_controller.dart';
import 'package:flutter/foundation.dart';

import 'workspace.dart';
import 'workspace_snapshot.dart';
import 'workspace_state.dart';
import 'workspace_store.dart';

/// Рабочие пространства: список, переключение со снимком состояния.
///
/// Decision: снимок собирает то, что видно контроллерам: видимые слои,
/// источник карты, метки на карте ([DisplayRegistry], если передан),
/// оповещения ([ProximityAlertController], если передан), а камеру и
/// формат координат UI сообщает через [updateCamera] и
/// [updateCoordsFormat]. Восстановленную камеру UI берёт из
/// [pendingCamera].
class WorkspaceController extends ChangeNotifier {
  WorkspaceController(
    this._store,
    this._layers,
    this._target,
    this._maps,
    this._navigation, {
    DisplayRegistry? display,
    ProximityAlertController? proximity,
    DateTime Function()? clock,
  }) : _display = display,
       _proximity = proximity,
       _clock = clock ?? DateTime.now;

  /// id пространства по умолчанию — тот же, под которым навигация хранила
  /// оповещения до появления пространств.
  static const String defaultId = NavigationSettings.defaultWorkspace;
  static const String defaultName = 'Default';

  final WorkspaceStore _store;
  final LayerStackController _layers;
  final TargetController _target;
  final MapsSettings _maps;
  final NavigationSettings _navigation;
  final DisplayRegistry? _display;
  final ProximityAlertController? _proximity;
  final DateTime Function() _clock;

  WorkspaceState _state = const WorkspaceState();
  WorkspaceSnapshot _current = const WorkspaceSnapshot();

  WorkspaceState get state => _state;

  /// Камера из снимка активного пространства — UI применяет её к карте.
  ({LandmarkLocation? center, double? zoom, double? bearing}) get pendingCamera =>
      (center: _current.mapCenter, zoom: _current.mapZoom, bearing: _current.mapBearing);

  /// Формат координат из снимка активного пространства.
  String? get coordsFormat => _current.primaryCoordsFormat;

  /// Загружает пространства; при первом запуске создаёт «Default».
  Future<void> load() async {
    var state = await _store.load();
    if (state.workspaces.isEmpty) {
      final now = _now();
      state = WorkspaceState(
        workspaces: [Workspace(id: defaultId, name: defaultName, createdAt: now, updatedAt: now)],
        activeId: defaultId,
      );
      await _store.saveList(state.workspaces, state.activeId);
    } else if (state.activeId == null) {
      state = WorkspaceState(workspaces: state.workspaces, activeId: state.workspaces.first.id);
      await _store.saveList(state.workspaces, state.activeId);
    }
    _state = state;
    await _enter(state.activeId!);
    notifyListeners();
  }

  /// Новое пространство (не активируется).
  Future<Workspace> create(String name) async {
    final trimmed = _name(name);
    final ws = Workspace.create(trimmed, now: _now());
    await _setList([..._state.workspaces, ws], _state.activeId);
    return ws;
  }

  Future<void> rename(String id, String newName) async {
    final trimmed = _name(newName);
    if (!_state.workspaces.any((w) => w.id == id)) throw StateError('No workspace $id');
    await _setList(
      [for (final w in _state.workspaces) w.id == id ? w.copyWith(name: trimmed, updatedAt: _now()) : w],
      _state.activeId,
    );
  }

  /// Удаляет пространство и его снимок; последнее — [StateError]. Активное
  /// перед удалением сменяется первым из оставшихся.
  Future<void> delete(String id) async {
    if (!_state.workspaces.any((w) => w.id == id)) return;
    if (_state.workspaces.length == 1) throw StateError('The last workspace cannot be deleted');
    if (_state.activeId == id) await activate(_state.workspaces.firstWhere((w) => w.id != id).id);
    await _setList([..._state.workspaces.where((w) => w.id != id)], _state.activeId);
    await _store.deleteSnapshot(id);
  }

  /// Сохраняет снимок текущего пространства, переходит в [id] и применяет
  /// его снимок.
  Future<void> activate(String id) async {
    if (!_state.workspaces.any((w) => w.id == id)) throw StateError('No workspace $id');
    if (id == _state.activeId) return;
    await snapshotCurrent();
    await _setList(_state.workspaces, id);
    await _enter(id);
    notifyListeners();
  }

  /// Сохраняет текущее состояние в снимок активного пространства.
  Future<void> snapshotCurrent() async {
    final id = _state.activeId;
    if (id == null) return;
    _current = _current.copyWith(
      displayedLayerIds: [for (final l in _layers.state.visibleLayers) l.id],
      currentSourceId: _maps.currentSource,
      displayedMarkerPaths: _display == null ? null : (_display.state.displayedPaths.toList()..sort()),
      proximityAlertIds: _proximity == null ? null : [for (final a in _proximity.alerts) a.id],
    );
    await _store.saveSnapshot(id, _current);
  }

  /// Положение карты (от UI) — попадёт в следующий снимок.
  void updateCamera({LandmarkLocation? center, double? zoom, double? bearing}) =>
      _current = _current.copyWith(mapCenter: center, mapZoom: zoom, mapBearing: bearing);

  void updateCoordsFormat(String? format) => _current = _current.copyWith(primaryCoordsFormat: format);

  /// Применяет снимок [id] к контроллерам.
  Future<void> _enter(String id) async {
    _current = await _store.loadSnapshot(id) ?? const WorkspaceSnapshot();
    await _navigation.setCurrentWorkspace(id);
    await _target.removeTarget();
    if (_current.displayedLayerIds.isNotEmpty) {
      for (final layer in _layers.state.stack) {
        await _layers.setVisible(layer.id, _current.displayedLayerIds.contains(layer.id));
      }
    }
    if (_current.currentSourceId != null) await _maps.setCurrentSource(_current.currentSourceId);
    final display = _display;
    if (display != null) {
      display
        ..clear()
        ..displayAll(_current.displayedMarkerPaths);
    }
    await _proximity?.load(id);
  }

  Future<void> _setList(List<Workspace> list, String? activeId) async {
    _state = WorkspaceState(workspaces: List.unmodifiable(list), activeId: activeId);
    await _store.saveList(_state.workspaces, activeId);
    notifyListeners();
  }

  static String _name(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    return trimmed;
  }

  int _now() => _clock().millisecondsSinceEpoch;
}
