import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../maps/color/erase_color_settings.dart';
import '../../models/layer_look.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';
import 'erase_color_range_dialog.dart';
import 'erase_color_screen.dart';
import 'erase_color_settings_providers.dart';
import 'look_panel.dart';

/// 🔧 экрана «Удалить цвет»: цвет под прицелом, диапазон, сброс.
class EraseColorToolsDialog extends ConsumerWidget {
  const EraseColorToolsDialog({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showDialog<void>(
        context: context,
        builder: (_) => EraseColorToolsDialog(sourceId: sourceId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    final under = navigator.context;
    final messenger = ScaffoldMessenger.of(context);
    // После закрытия окна его ref недоступен — читаем через контейнер.
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(mapLayersProvider.notifier);
    LayerLook look() => container.read(layerLooksProvider)[sourceId] ?? const LayerLook();

    Future<void> setErase(EraseColorSettings erase, String message) async {
      try {
        await notifier.setLook(sourceId, look().copyWith(erase: erase));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      } on LayerException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    Future<void> pickCenter() async {
      final width = container.read(colorRangesWidthProvider);
      final argb = await container.read(centerPixelProvider)();
      navigator.pop();
      if (argb == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Цвет недоступен')));
        return;
      }
      await setErase(
        eraseWith([(argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF], width),
        'Цвет взят из-под прицела',
      );
    }

    Widget item(String key, IconData icon, String label, VoidCallback onTap) => InkWell(
          key: Key(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: const Color(0xFF00A38E)),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF212121)))),
              ],
            ),
          ),
        );

    return AlertDialog(
      title: const Text(
        'Удалить цвет',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          item('erase_tools_center', Icons.center_focus_weak, 'Для удаления использовать цвет под центром экрана',
              pickCenter),
          item('erase_tools_range', Icons.unfold_more, 'Диапазон удаления', () {
            navigator.pop();
            EraseColorRangeDialog.show(under, sourceId);
          }),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        LookDialogButton(
          key: const Key('erase_tools_reset'),
          label: 'СБРОСИТЬ',
          onPressed: () {
            navigator.pop();
            setErase(EraseColorSettings.empty(), 'Настройки удаления цвета сброшены');
          },
        ),
        LookDialogButton(key: const Key('erase_tools_cancel'), label: 'ОТМЕНА', onPressed: () => navigator.pop()),
      ],
    );
  }
}
