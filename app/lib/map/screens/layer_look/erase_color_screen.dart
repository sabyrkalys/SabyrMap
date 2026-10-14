import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../maps/color/color_range.dart';
import '../../../maps/color/erase_color_settings.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'erase_color_settings_providers.dart';
import 'erase_color_tools_dialog.dart';
import 'look_panel.dart';

/// Диапазоны удаления [erase] по трём каналам с шириной [width]; без них —
/// вокруг чёрного.
List<ColorRange> eraseRanges(EraseColorSettings erase, int width) {
  final ranges = erase.ranges.length == 3 ? erase.ranges : EraseColorSettings.empty().ranges;
  return [for (final r in ranges) ColorRange(channel: r.channel, center: r.center, width: width)];
}

/// Удаление включено с центрами [centers] (R, G, B) и шириной [width].
EraseColorSettings eraseWith(List<int> centers, int width) =>
    EraseColorSettings.fromColor(0xFF000000 | centers[0] << 16 | centers[1] << 8 | centers[2], width: width);

/// «Удалить цвет»: центры r, g, b удаляемого цвета; ширина диапазона общая
/// (🔧 → «Диапазон удаления»). Изменения сразу сохраняются в виде слоя.
class EraseColorScreen extends ConsumerWidget {
  const EraseColorScreen({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) =>
      showLookPanel(context, EraseColorScreen(sourceId: sourceId));

  static const _channels = ['r', 'g', 'b'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(layerLooksProvider)[sourceId] ?? const LayerLook();
    final width = ref.watch(colorRangesWidthProvider);
    final ranges = eraseRanges(look.erase, width);
    final centers = [for (final r in ranges) r.center];
    final name = layerTitle(ref.watch(mapLayersProvider), ref.watch(catalogProvider).value ?? const [], sourceId);

    // Берёт вид слоя на момент изменения: несколько изменений до перерисовки
    // не затирают друг друга.
    void setCenter(int channel, int center) {
      final current = ref.read(layerLooksProvider)[sourceId] ?? const LayerLook();
      final next = [for (final r in eraseRanges(current.erase, width)) r.center]..[channel] = center;
      runLayerChange(
        context,
        () => ref.read(mapLayersProvider.notifier).setLook(sourceId, current.copyWith(erase: eraseWith(next, width))),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LookAppBar(
          icon: Icons.colorize,
          title: 'Удалить цвет · $name',
          onHelp: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Пиксели слоя около выбранного цвета (± диапазон по каждому каналу) становятся прозрачными.'),
          )),
          onTools: () => EraseColorToolsDialog.show(context, sourceId),
          onDone: () => Navigator.of(context).pop(),
        ),
        LookSliders(children: [
          for (var c = 0; c < 3; c++)
            LookSliderRow(
              key: Key('erase_${_channels[c]}'),
              minLabel: '0',
              label: EraseRangeLabel(channel: _channels[c], range: ranges[c]),
              maxLabel: '255',
              value: centers[c].toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: (v) => setCenter(c, v.round()),
            ),
        ]),
      ],
    );
  }
}

/// «r: 53 58 63» — нижняя граница, центр крупно, верхняя граница.
class EraseRangeLabel extends StatelessWidget {
  const EraseRangeLabel({super.key, required this.channel, required this.range});

  final String channel;
  final ColorRange range;

  int get low => (range.center - range.width).clamp(0, 255);
  int get high => (range.center + range.width).clamp(0, 255);

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 15, color: Color(0xFF212121));
    return Text.rich(
      TextSpan(
        style: small,
        children: [
          TextSpan(text: '$channel: ', style: const TextStyle(fontSize: 22)),
          TextSpan(text: '$low '),
          TextSpan(text: '${range.center}', style: const TextStyle(fontSize: 26)),
          TextSpan(text: ' $high'),
        ],
      ),
      key: Key('erase_label_$channel'),
    );
  }
}
