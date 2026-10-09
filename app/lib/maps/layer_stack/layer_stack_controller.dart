import 'dart:convert';

import 'package:app/maps/color/erase_color_settings.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:flutter/foundation.dart';

import 'layer_blending.dart';
import 'layer_entry.dart';
import 'layer_state.dart';

/// Стек слоёв карты. Каждая правка пересчитывает порядок (0 — нижний) и
/// сохраняется в настройки, чтобы стек восстановился при старте.
class LayerStackController extends ChangeNotifier {
  LayerStackController(this._settings);

  final MapsSettings _settings;
  LayerState _state = const LayerState();

  LayerState get state => _state;

  /// Восстанавливает стек из настроек; повреждённая запись — пустой стек.
  Future<void> load() async {
    final raw = _settings.layerStackJson;
    var layers = <LayerEntry>[];
    if (raw != null) {
      try {
        layers = [for (final e in jsonDecode(raw) as List<dynamic>) LayerEntry.fromJson(e as Map<String, dynamic>)]
          ..sort((a, b) => a.order.compareTo(b.order));
      } on Object {
        layers = [];
      }
    }
    _state = LayerState(stack: _renumber(layers));
    notifyListeners();
  }

  /// Кладёт слой наверх и выбирает его. Тот же id — [ArgumentError].
  Future<void> add(LayerEntry entry) async {
    if (_state.stack.any((l) => l.id == entry.id)) throw ArgumentError.value(entry.id, 'id', 'already in the stack');
    await _apply([..._state.stack, entry], selected: entry.id);
  }

  /// Убирает слой; если он был выбран — выбор снимается.
  Future<void> remove(String layerId) async {
    if (!_has(layerId)) return;
    await _apply(
      [..._state.stack.where((l) => l.id != layerId)],
      selected: _state.selectedLayerId == layerId ? null : _state.selectedLayerId,
    );
  }

  /// На одну позицию выше (к верху стека).
  Future<void> moveUp(String layerId) async {
    final i = _index(layerId);
    if (i < 0 || i == _state.count - 1) return;
    await reorder(layerId, i + 1);
  }

  /// На одну позицию ниже.
  Future<void> moveDown(String layerId) async {
    final i = _index(layerId);
    if (i <= 0) return;
    await reorder(layerId, i - 1);
  }

  /// Переносит слой на позицию [newIndex] (ограничивается стеком).
  Future<void> reorder(String layerId, int newIndex) async {
    final i = _index(layerId);
    if (i < 0) return;
    final stack = [..._state.stack];
    final layer = stack.removeAt(i);
    stack.insert(newIndex.clamp(0, stack.length), layer);
    await _apply(stack);
  }

  /// Прозрачность, ограничивается [0, 1].
  Future<void> setOpacity(String layerId, double value) =>
      _update(layerId, (l) => l.copyWith(opacity: value.clamp(0.0, 1.0)));

  Future<void> setVisible(String layerId, bool value) => _update(layerId, (l) => l.copyWith(visible: value));

  Future<void> setBlending(String layerId, LayerBlending blending) =>
      _update(layerId, (l) => l.copyWith(blending: blending));

  Future<void> setColor(String layerId, LayerColorSettings color) => _update(layerId, (l) => l.copyWith(color: color));

  Future<void> setEraseColor(String layerId, EraseColorSettings? erase) =>
      _update(layerId, (l) => l.copyWith(eraseColor: erase));

  void select(String? layerId) {
    if (layerId != null && !_has(layerId)) return;
    _state = LayerState(stack: _state.stack, selectedLayerId: layerId);
    notifyListeners();
  }

  /// Заменяет весь стек (например, избранным набором); порядок — по [layers].
  Future<void> replaceAll(List<LayerEntry> layers) => _apply(layers);

  Future<void> clear() => _apply(const []);

  /// Сохраняет стек в настройки.
  Future<void> persist() => _settings.setLayerStackJson(jsonEncode([for (final l in _state.stack) l.toJson()]));

  Future<void> _update(String layerId, LayerEntry Function(LayerEntry) change) async {
    if (!_has(layerId)) return;
    await _apply([for (final l in _state.stack) l.id == layerId ? change(l) : l]);
  }

  Future<void> _apply(List<LayerEntry> layers, {Object? selected = _keep}) async {
    final stack = _renumber(layers);
    final id = identical(selected, _keep) ? _state.selectedLayerId : selected as String?;
    _state = LayerState(stack: stack, selectedLayerId: stack.any((l) => l.id == id) ? id : null);
    notifyListeners();
    await persist();
  }

  static const Object _keep = Object();

  static List<LayerEntry> _renumber(List<LayerEntry> layers) =>
      List.unmodifiable([for (final (i, l) in layers.indexed) l.order == i ? l : l.copyWith(order: i)]);

  int _index(String id) => _state.stack.indexWhere((l) => l.id == id);
  bool _has(String id) => _index(id) >= 0;
}
