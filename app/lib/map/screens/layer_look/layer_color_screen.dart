import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../maps/color/layer_color_settings.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'layer_color_tools_dialog.dart';
import 'look_panel.dart';

const TextStyle _valueStyle = TextStyle(fontSize: 22, color: Color(0xFF212121));

/// «Изменить цвет»: контрастность, яркость, насыщенность и оттенок слоя;
/// карта меняется сразу, ✓ закрывает экран.
class LayerColorScreen extends ConsumerWidget {
  const LayerColorScreen({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) =>
      showLookPanel(context, LayerColorScreen(sourceId: sourceId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(layerLooksProvider)[sourceId] ?? const LayerLook();
    final color = look.color;
    final name = layerTitle(ref.watch(mapLayersProvider), ref.watch(catalogProvider).value ?? const [], sourceId);
    // Берёт вид слоя на момент изменения: несколько изменений до перерисовки
    // не затирают друг друга.
    void apply(LayerColorSettings Function(LayerColorSettings current) change) {
      final current = ref.read(layerLooksProvider)[sourceId] ?? const LayerLook();
      runLayerChange(
        context,
        () => ref.read(mapLayersProvider.notifier).setLook(sourceId, current.copyWith(color: change(current.color))),
      );
    }

    Widget row(
      String key,
      String title,
      double percent,
      double min,
      double max,
      LayerColorSettings Function(LayerColorSettings color, double value) to,
    ) =>
        LookSliderRow(
          key: Key('color_$key'),
          minLabel: '${min.round()} %',
          label: Text('$title: ${percent.round()} %', style: _valueStyle),
          maxLabel: '${max.round()} %',
          value: percent,
          min: min,
          max: max,
          onChanged: (v) => apply((color) => to(color, v.roundToDouble())),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LookAppBar(
          icon: Icons.palette,
          title: 'Изменить цвет · $name',
          onHelp: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Слайдеры меняют слой сразу. Инверсия и сброс — в «Инструментах» (🔧).'),
          )),
          onTools: () => LayerColorToolsDialog.show(context, sourceId),
          onDone: () => Navigator.of(context).pop(),
        ),
        LookSliders(children: [
          row('contrast', 'Контрастность', color.contrast * 100, 0, 200, (c, v) => c.copyWith(contrast: v / 100)),
          row('brightness', 'Яркость', (color.brightness + 1) * 100, 0, 200,
              (c, v) => c.copyWith(brightness: v / 100 - 1)),
          row('saturation', 'Насыщенность', color.saturation * 100, 0, 200,
              (c, v) => c.copyWith(saturation: v / 100)),
          row('hue', 'Оттенок', color.hue * 100, -100, 100, (c, v) => c.copyWith(hue: v / 100)),
        ]),
      ],
    );
  }
}
