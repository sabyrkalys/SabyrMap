import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_icons.dart';
import '../../widgets/app_icon.dart';
import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../services/layer_manager.dart';
import '../state/map_layers_controller.dart';
import 'available_maps_screen.dart';

/// «Карты на экране»: the base map, the overlays laid over it (order,
/// visibility, opacity) and presets. Changes apply to the map at once.
class LayersPanel extends ConsumerStatefulWidget {
  const LayersPanel({super.key});

  /// Shown when no base was chosen yet: the map starts with this style.
  static const String defaultBaseId = 'ofm-liberty';

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  /// Opacity while a slider is being dragged, before it is applied.
  final Map<String, double> _dragging = {};

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on LayerException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _addLayer(bool baseIsolated) async {
    if (baseIsolated) {
      _message(LayerManager.isolatedMessage);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const AvailableMapsScreen(pickOverlay: true)));
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(catalogProvider).value ?? const <MapProvider>[];
    final state = ref.watch(mapLayersProvider);
    final notifier = ref.read(mapLayersProvider.notifier);
    final sources = {for (final p in providers) for (final s in p.sources) s.id: s};
    final isolatedIds = {for (final p in providers) if (p.isolated) ...p.sources.map((s) => s.id)};
    final baseId = state.baseSourceId ?? LayersPanel.defaultBaseId;
    final baseIsolated = isolatedIds.contains(baseId);
    // Shown top → bottom, i.e. highest zIndex first.
    final shown = state.overlays.reversed.toList();
    final headerStyle = Theme.of(context).textTheme.titleSmall;

    return Scaffold(
      appBar: AppBar(title: const Text('Карты на экране')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Базовая подложка', style: headerStyle),
          ),
          RadioGroup<String>(
            groupValue: baseId,
            onChanged: (id) {
              final source = id == null ? null : sources[id];
              if (source == null) return;
              _run(() async {
                final result = await notifier.setBase(source);
                if (!result.ok) _message(result.problems.join('\n'));
              });
            },
            child: Column(
              children: [
                for (final provider in providers)
                  for (final source in provider.sources)
                    RadioListTile<String>(
                      key: Key('base_${source.id}'),
                      value: source.id,
                      title: Text(source.name),
                      subtitle: Text('${provider.name} · ${storageModeLabel(source.storageMode)}'),
                    ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Наложенные слои (${state.overlays.length}/${notifier.maxOverlays})', style: headerStyle),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              final order = shown.map((l) => l.sourceId).toList();
              final moved = order.removeAt(oldIndex);
              order.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
              _run(() => notifier.reorderOverlays(order.reversed.toList()));
            },
            children: [
              for (var i = 0; i < shown.length; i++)
                _OverlayRow(
                  key: ValueKey(shown[i].sourceId),
                  index: i,
                  layer: shown[i],
                  name: sources[shown[i].sourceId]?.name ?? shown[i].sourceId,
                  opacity: _dragging[shown[i].sourceId] ?? shown[i].opacity,
                  onVisible: (v) => _run(() => notifier.setVisibility(shown[i].sourceId, v)),
                  onOpacityDrag: (v) => setState(() => _dragging[shown[i].sourceId] = v),
                  onOpacitySet: (v) => _run(() async {
                    await notifier.setOpacity(shown[i].sourceId, v);
                    if (mounted) setState(() => _dragging.remove(shown[i].sourceId));
                  }),
                  onDelete: () => _run(() => notifier.removeOverlay(shown[i].sourceId)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => _addLayer(baseIsolated), child: const Text('+ Добавить слой')),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Пресеты', style: headerStyle),
          ),
          for (final preset in state.presets)
            ListTile(
              key: Key('preset_${preset.id}'),
              leading: const AppIcon(AppIcons.layers),
              title: Text(preset.name),
              onTap: () => _run(() async {
                final result = await notifier.applyPreset(preset);
                if (!result.ok) _message(result.problems.join('\n'));
              }),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OverlayRow extends StatelessWidget {
  const _OverlayRow({
    super.key,
    required this.index,
    required this.layer,
    required this.name,
    required this.opacity,
    required this.onVisible,
    required this.onOpacityDrag,
    required this.onOpacitySet,
    required this.onDelete,
  });

  final int index;
  final ActiveLayer layer;
  final String name;
  final double opacity;
  final ValueChanged<bool> onVisible;
  final ValueChanged<double> onOpacityDrag;
  final ValueChanged<double> onOpacitySet;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
          Checkbox(
            key: Key('overlay_visible_${layer.sourceId}'),
            value: layer.visible,
            onChanged: (v) => onVisible(v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name)),
                    Text('${(opacity * 100).round()}%'),
                  ],
                ),
                Slider(
                  key: Key('overlay_opacity_${layer.sourceId}'),
                  value: opacity.clamp(0.0, 1.0),
                  onChanged: onOpacityDrag,
                  onChangeEnd: onOpacitySet,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('overlay_delete_${layer.sourceId}'),
            icon: const AppIcon(AppIcons.trash),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
