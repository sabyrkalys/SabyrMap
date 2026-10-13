import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';

/// Основа под-шторок вида слоя: изменения применяются сразу; «ОТМЕНА»
/// возвращает вид, бывший при открытии, «СБРОСИТЬ» — исходный.
abstract class LayerLookSheet extends ConsumerStatefulWidget {
  const LayerLookSheet({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> open(BuildContext context, Widget sheet) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        builder: (_) => sheet,
      );
}

abstract class LayerLookSheetState<T extends LayerLookSheet> extends ConsumerState<T> {
  /// Вид при открытии — для «ОТМЕНА».
  late final LayerLook initial;

  @override
  void initState() {
    super.initState();
    initial = ref.read(layerLooksProvider.notifier).of(widget.sourceId);
  }

  LayerLook get look => ref.watch(layerLooksProvider)[widget.sourceId] ?? const LayerLook();

  void apply(LayerLook look) => runLayerChange(context, () => ref.read(mapLayersProvider.notifier).setLook(widget.sourceId, look));

  /// Вид после «СБРОСИТЬ».
  LayerLook reset(LayerLook look);

  String get title;

  List<Widget> buildBody(BuildContext context, LayerLook look);

  @override
  Widget build(BuildContext context) {
    final name = layerName(ref.watch(catalogProvider).value ?? const [], widget.sourceId);
    final look = this.look;
    final navigator = Navigator.of(context);
    return SheetMenu(
      title: '$title · $name',
      children: [
        ...buildBody(context, look),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              key: const Key('look_reset'),
              style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
              onPressed: () => apply(reset(look)),
              child: const Text('СБРОСИТЬ', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
            const Spacer(),
            TextButton(
              key: const Key('look_cancel'),
              style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
              onPressed: () {
                apply(initial);
                navigator.pop();
              },
              child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
            TextButton(
              key: const Key('look_ok'),
              style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
              onPressed: () => navigator.pop(),
              child: const Text('ОК', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Подпись, значение и слайдер в цветах шторок.
class LookSlider extends StatelessWidget {
  const LookSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.color = SheetMenuColors.accent,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: SheetMenuColors.text))),
              Text('${value.round()}', style: const TextStyle(fontSize: 15, color: SheetMenuColors.secondary)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(activeTrackColor: color, inactiveTrackColor: const Color(0xFFE0E0E0), thumbColor: color),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ],
      );
}
