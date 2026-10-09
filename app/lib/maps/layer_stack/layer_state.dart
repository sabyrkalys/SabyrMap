import 'layer_entry.dart';

/// Стек слоёв карты.
class LayerState {
  const LayerState({this.stack = const [], this.selectedLayerId});

  /// [0] — нижний слой.
  final List<LayerEntry> stack;
  final String? selectedLayerId;

  List<LayerEntry> get visibleLayers => [for (final l in stack) if (l.visible) l];

  LayerEntry? get selected => stack.where((l) => l.id == selectedLayerId).firstOrNull;

  int get count => stack.length;
}
