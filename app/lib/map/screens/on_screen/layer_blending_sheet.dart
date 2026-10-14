import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../../maps/layer_stack/layer_blending.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';

/// Подпись режима смешивания.
String blendingLabel(LayerBlending mode) => switch (mode) {
      LayerBlending.normal => 'Нормальный (по умолчанию)',
      LayerBlending.lighten => 'Замена светлым',
      LayerBlending.screen => 'Экран',
      LayerBlending.overlay => 'Перекрытие',
      LayerBlending.multiply => 'Умножение',
      LayerBlending.darken => 'Затенение',
    };

/// «Режим смешивания слоёв»: один режим из [LayerBlending].
class LayerBlendingSheet extends ConsumerWidget {
  const LayerBlendingSheet({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LayerBlendingSheet(sourceId: sourceId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(layerLooksProvider)[sourceId] ?? const LayerLook();
    final navigator = Navigator.of(context);
    return SheetMenu(
      title: 'Режим смешивания слоёв',
      children: [
        RadioGroup<LayerBlending>(
          groupValue: look.blending,
          onChanged: (mode) {
            if (mode == null) return;
            final messenger = ScaffoldMessenger.of(context);
            runLayerChange(context, () => ref.read(mapLayersProvider.notifier).setLook(sourceId, look.copyWith(blending: mode)));
            navigator.pop();
            messenger.showSnackBar(SnackBar(content: Text('Режим: ${blendingLabel(mode)}')));
          },
          child: Column(
            children: [
              for (final mode in LayerBlending.values)
                RadioListTile<LayerBlending>(
                  key: Key('blending_${mode.name}'),
                  contentPadding: EdgeInsets.zero,
                  value: mode,
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? SheetMenuColors.text : SheetMenuColors.secondary,
                  ),
                  title: Text(blendingLabel(mode), style: const TextStyle(fontSize: 16, color: SheetMenuColors.text)),
                ),
            ],
          ),
        ),
        SheetMenuCancel(onPressed: () => navigator.pop()),
      ],
    );
  }
}
