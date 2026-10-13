import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/catalog_repository.dart';
import '../../state/map_layers_controller.dart';
import 'compare_mode_bottom_panel.dart';
import 'compare_mode_controller.dart';
import 'compare_select_dialog.dart';

/// Слои, которые сейчас сравниваются (сверху вниз); null — режим выключен.
/// Не сохраняется между запусками.
class CompareRequestNotifier extends Notifier<List<String>?> {
  @override
  List<String>? build() => null;

  void start(List<String> layerIds) => state = List.unmodifiable(layerIds);

  void stop() => state = null;
}

final compareRequestProvider = NotifierProvider<CompareRequestNotifier, List<String>?>(CompareRequestNotifier.new);

/// Режим сравнения поверх основной карты: на карте из наложенных слоёв
/// виден только выбранный слайдером (для базовой карты — ни один);
/// ортофотопланы не трогаются. Видимость меняется только на карте, без
/// сохранения; при выходе (✕ или «назад») всё возвращается как было.
class CompareModeScreen extends ConsumerStatefulWidget {
  const CompareModeScreen({super.key, required this.layerIds});

  final List<String> layerIds;

  @override
  ConsumerState<CompareModeScreen> createState() => _CompareModeScreenState();
}

class _CompareModeScreenState extends ConsumerState<CompareModeScreen> {
  late final CompareModeController _controller = CompareModeController(widget.layerIds);
  late final MapStateNotifier _layers = ref.read(mapLayersProvider.notifier);

  /// Видимость наложенных слоёв при входе.
  late final Map<String, bool> _snapshot = {
    for (final l in ref.read(mapLayersProvider).overlays) l.sourceId: l.visible,
  };

  @override
  void initState() {
    super.initState();
    _controller.addListener(_show);
    _show();
  }

  Future<void> _show() async {
    final current = _controller.currentLayerId;
    for (final id in _snapshot.keys) {
      try {
        await _layers.previewVisibility(id, id == current);
      } on Object {
        // Слой убран или карта ещё не готова — пропускаем.
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_show);
    _controller.dispose();
    for (final entry in _snapshot.entries) {
      _layers.previewVisibility(entry.key, entry.value).catchError((Object _) {});
    }
    super.dispose();
  }

  void _close() => ref.read(compareRequestProvider.notifier).stop();

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final c in compareCandidates(ref.watch(mapLayersProvider), ref.watch(catalogProvider).value ?? const []))
        c.id: c.name,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CompareModeBottomPanel(controller: _controller, names: names, onClose: _close),
    );
  }
}
