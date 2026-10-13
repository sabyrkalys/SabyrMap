import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../services/layer_manager.dart';
import '../state/map_layers_controller.dart';
import 'available_maps_screen.dart';
import 'on_screen/layer_context_menu.dart';
import 'on_screen/layer_opacity_sheet.dart';
import 'on_screen/on_screen_layer_row.dart';
import 'on_screen/on_screen_layers_header.dart';

/// Фон панели «Карты на экране» и её под-экранов.
const Color onScreenPanelBackground = Color(0xFFEEF1F5);

/// Все источники каталога по id, с их поставщиком.
Map<String, ({MapProvider provider, MapSource source})> catalogIndex(List<MapProvider> providers) => {
  for (final p in providers)
    for (final s in p.sources) s.id: (provider: p, source: s),
};

/// Выполняет изменение слоёв; отказ карты ([LayerException]) — SnackBar.
Future<void> runLayerChange(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
  } on LayerException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// «Карты на экране»: наложенные слои сверху вниз (верхний слой карты —
/// первым) и базовая карта последней. Шторка поверх карты, чтобы
/// изменения были видны сразу.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({super.key});

  /// Показывается, пока базовая карта не выбрана: карта стартует с неё.
  static const String defaultBaseId = CatalogRepository.defaultBaseSourceId;

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black12,
    builder: (_) => const LayersPanel(),
  );

  /// Панель прячется, пока открыта шторка непрозрачности (карта видна
  /// целиком), и возвращается, когда шторку закрыли.
  static Future<void> _openOpacity(BuildContext context, String sourceId) async {
    final navigator = Navigator.of(context);
    final under = navigator.context;
    navigator.pop();
    await LayerOpacitySheet.show(under, sourceId);
    if (under.mounted) await show(under);
  }

  Future<void> _addLayer(BuildContext context, bool baseIsolated) async {
    if (baseIsolated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(LayerManager.isolatedMessage)));
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<bool>(builder: (_) => const AvailableMapsScreen(pickOverlay: true)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(catalogProvider).value ?? const <MapProvider>[];
    final state = ref.watch(mapLayersProvider);
    final notifier = ref.read(mapLayersProvider.notifier);
    final index = catalogIndex(providers);
    final baseId = state.baseSourceId ?? defaultBaseId;
    final baseIsolated = index[baseId]?.provider.isolated ?? false;
    // Сверху вниз, т. е. с наибольшего zIndex.
    final shown = state.overlays.reversed.toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: Container(
        decoration: const BoxDecoration(
          color: onScreenPanelBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 12)],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnScreenLayersHeader(),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Порядок — ручкой ≡ (долгий тап по строке открывает меню).
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorderItem: (oldIndex, newIndex) {
                            final order = shown.map((l) => l.sourceId).toList();
                            order.insert(newIndex, order.removeAt(oldIndex));
                            runLayerChange(context, () => notifier.reorderOverlays(order.reversed.toList()));
                          },
                          children: [
                            for (final (i, layer) in shown.indexed)
                              OnScreenLayerRow(
                                key: ValueKey(layer.sourceId),
                                index: i,
                                layer: layer,
                                name: index[layer.sourceId]?.source.name ?? layer.sourceId,
                                source: index[layer.sourceId]?.source,
                                onVisible: (v) =>
                                    runLayerChange(context, () => notifier.setVisibility(layer.sourceId, v)),
                                onOpacity: () => _openOpacity(context, layer.sourceId),
                                onMenu: () => LayerContextMenu.show(context, layer.sourceId),
                              ),
                          ],
                        ),
                        OnScreenLayerBaseRow(
                          name: index[baseId]?.source.name ?? baseId,
                          source: index[baseId]?.source,
                          onTap: () => Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => const AvailableMapsScreen())),
                          onMenu: () => LayerContextMenu.show(context, LayerContextMenu.baseId),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const Key('layers_add'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                            onPressed: () => _addLayer(context, baseIsolated),
                            icon: const Icon(Icons.add),
                            label: Text('Добавить слой (${state.overlays.length}/${notifier.maxOverlays})'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
