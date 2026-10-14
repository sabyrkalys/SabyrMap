import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../../maps/color/erase_color_settings.dart';
import '../../models/layer_look.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';
import 'erase_color_screen.dart';
import 'erase_color_settings_providers.dart';
import 'look_panel.dart';

/// «Диапазон удаления»: ±N по каждому каналу; выбор сразу применяется,
/// запоминается и закрывает окно.
class EraseColorRangeDialog extends ConsumerWidget {
  const EraseColorRangeDialog({super.key, required this.sourceId});

  final String sourceId;

  static const List<int> widths = [1, 3, 5, 9, 15, 23];

  /// Выбранная ширина или null («ОТМЕНА»).
  static Future<int?> show(BuildContext context, String sourceId) => showDialog<int>(
        context: context,
        builder: (_) => EraseColorRangeDialog(sourceId: sourceId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(colorRangesWidthProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // После закрытия окна его ref недоступен — читаем через контейнер.
    final container = ProviderScope.containerOf(context, listen: false);

    Future<void> pick(int width) async {
      navigator.pop(width);
      await container.read(colorRangesWidthProvider.notifier).set(width);
      final look = container.read(layerLooksProvider)[sourceId] ?? const LayerLook();
      // Включённое удаление пересчитывается на новую ширину.
      if (look.erase.enabled) {
        final centers = [for (final r in eraseRanges(look.erase, width)) r.center];
        try {
          await container.read(mapLayersProvider.notifier).setLook(sourceId, look.copyWith(erase: eraseWith(centers, width)));
        } on LayerException catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
          return;
        }
      } else if (look.erase.ranges.isNotEmpty) {
        await container.read(mapLayersProvider.notifier).setLook(
              sourceId,
              look.copyWith(erase: EraseColorSettings(ranges: eraseRanges(look.erase, width))),
            );
      }
      messenger.showSnackBar(SnackBar(content: Text('Диапазон: ±$width')));
    }

    return AlertDialog(
      title: const Text(
        'Диапазон удаления',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
      ),
      content: RadioGroup<int>(
        groupValue: current,
        onChanged: (w) {
          if (w != null) pick(w);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in widths)
              RadioListTile<int>(
                key: Key('erase_range_$w'),
                contentPadding: EdgeInsets.zero,
                value: w,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? SheetMenuColors.text : SheetMenuColors.secondary,
                ),
                title: Text('±$w', style: const TextStyle(fontSize: 16, color: SheetMenuColors.text)),
              ),
          ],
        ),
      ),
      actions: [LookDialogButton(key: const Key('erase_range_cancel'), label: 'ОТМЕНА', onPressed: () => navigator.pop())],
    );
  }
}
