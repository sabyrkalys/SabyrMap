import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import '../on_screen/layer_context_menu.dart';

/// Что можно сравнить: наложенные слои сверху вниз, выбранную карту
/// ([LayerContextMenu.baseId]) и встроенную «Базовую карту»; ортофотопланы не
/// сравниваются.
List<({String id, String name})> compareCandidates(MapState state, List<MapProvider> providers) {
  final baseId = state.baseSourceId ?? LayersPanel.defaultBaseId;
  return [
    for (final layer in state.overlays.reversed) (id: layer.sourceId, name: layerName(providers, layer.sourceId)),
    if (baseId != LayerManager.noMapId) (id: LayerContextMenu.baseId, name: '${layerName(providers, baseId)} (карта)'),
    (id: MapStateNotifier.worldKey, name: 'Базовая карта'),
  ];
}

/// Строка выбора: чекбокс и имя слоя.
class CompareSelectTile extends StatelessWidget {
  const CompareSelectTile({super.key, required this.name, required this.selected, required this.onChanged});

  final String name;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!selected),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Checkbox(value: selected, activeColor: SheetMenuColors.accent, onChanged: (v) => onChanged(v ?? false)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 16, color: SheetMenuColors.text)),
          ),
        ],
      ),
    ),
  );
}

/// «Сравнить...»: выбор 2+ слоёв; по умолчанию отмечен [sourceId].
/// Возвращает id выбранных сверху вниз или null.
class CompareSelectDialog extends ConsumerStatefulWidget {
  const CompareSelectDialog({super.key, required this.sourceId});

  final String sourceId;

  static Future<List<String>?> show(BuildContext context, String sourceId) => showDialog<List<String>>(
    context: context,
    builder: (_) => CompareSelectDialog(sourceId: sourceId),
  );

  @override
  ConsumerState<CompareSelectDialog> createState() => _CompareSelectDialogState();
}

class _CompareSelectDialogState extends ConsumerState<CompareSelectDialog> {
  late final Set<String> _selected = {widget.sourceId};

  @override
  Widget build(BuildContext context) {
    final candidates = compareCandidates(ref.watch(mapLayersProvider), ref.watch(catalogProvider).value ?? const []);
    final buttonStyle = TextButton.styleFrom(foregroundColor: SheetMenuColors.accent);
    return AlertDialog(
      title: const Text('Сравнить...'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in candidates)
              CompareSelectTile(
                key: Key('compare_select_${c.id}'),
                name: c.name,
                selected: _selected.contains(c.id),
                onChanged: (v) => setState(() => v ? _selected.add(c.id) : _selected.remove(c.id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(style: buttonStyle, onPressed: () => Navigator.of(context).pop(), child: const Text('ОТМЕНА')),
        TextButton(
          key: const Key('compare_select_ok'),
          style: buttonStyle,
          onPressed: () {
            final ids = [
              for (final c in candidates)
                if (_selected.contains(c.id)) c.id,
            ];
            if (ids.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите хотя бы 2 слоя')));
              return;
            }
            Navigator.of(context).pop(ids);
          },
          child: const Text('ОК'),
        ),
      ],
    );
  }
}
