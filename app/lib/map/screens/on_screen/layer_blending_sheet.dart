import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../../maps/layer_stack/layer_blending.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';

/// Подпись режима смешивания.
String blendingLabel(LayerBlending mode) => switch (mode) {
      LayerBlending.normal => 'Обычный',
      LayerBlending.multiply => 'Умножение',
      LayerBlending.screen => 'Осветление (экран)',
      LayerBlending.overlay => 'Перекрытие',
      LayerBlending.darken => 'Замена тёмным',
      LayerBlending.lighten => 'Замена светлым',
      LayerBlending.softLight => 'Мягкий свет',
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
            runLayerChange(context, () => ref.read(mapLayersProvider.notifier).setLook(sourceId, look.copyWith(blending: mode)));
            navigator.pop();
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
