import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../maps/color/layer_color_settings.dart';
import '../../models/layer_look.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'look_panel.dart';

/// «Инструменты» экрана «Изменить цвет»: инверсия цветов и сброс.
class LayerColorToolsDialog extends ConsumerWidget {
  const LayerColorToolsDialog({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showDialog<void>(
        context: context,
        builder: (_) => LayerColorToolsDialog(sourceId: sourceId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(layerLooksProvider)[sourceId] ?? const LayerLook();
    final notifier = ref.read(mapLayersProvider.notifier);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> reset() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: const Key('color_reset_confirm'),
          title: const Text(
            'Сбросить настройки цвета?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
          ),
          content: const Text(
            'Контрастность, яркость, насыщенность, оттенок и инверсия вернутся к значениям по умолчанию.',
            style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
          ),
          actions: [
            LookDialogButton(label: 'ОТМЕНА', onPressed: () => Navigator.of(dialog).pop(false)),
            LookDialogButton(
              key: const Key('color_reset_ok'),
              label: 'СБРОСИТЬ',
              onPressed: () => Navigator.of(dialog).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      navigator.pop();
      try {
        await notifier.setLook(sourceId, look.copyWith(color: LayerColorSettings.identity()));
        messenger.showSnackBar(const SnackBar(content: Text('Настройки цвета сброшены')));
      } on LayerException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return AlertDialog(
      title: const Text(
        'Инструменты',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
      ),
      content: InkWell(
        key: const Key('color_tools_invert'),
        onTap: () => runLayerChange(
          context,
          () => notifier.setLook(sourceId, look.copyWith(color: look.color.copyWith(inverted: !look.color.inverted))),
        ),
        child: Row(
          children: [
            IgnorePointer(
              child: Checkbox(
                value: look.color.inverted,
                activeColor: const Color(0xFF00A38E),
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Инверсия цветов', style: TextStyle(fontSize: 16, color: Color(0xFF212121)))),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        LookDialogButton(key: const Key('color_tools_reset'), label: 'СБРОСИТЬ', onPressed: reset),
        LookDialogButton(key: const Key('color_tools_cancel'), label: 'ОТМЕНА', onPressed: () => navigator.pop()),
      ],
    );
  }
}
