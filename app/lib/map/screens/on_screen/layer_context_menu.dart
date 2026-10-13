import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialogs/confirm_dialog.dart';
import '../../../explorer/sheet_menu.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/layer_look.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import 'force_refresh_dialog.dart';
import 'layer_blending_sheet.dart';
import 'layer_color_sheet.dart';
import 'layer_details_sheet.dart';
import 'layer_erase_color_sheet.dart';
import 'layer_opacity_sheet.dart';

/// Меню слоя «Карт на экране»: детали, порядок и вид слоя. Для базовой
/// карты ([baseId]) доступны только детали: её не убрать и не изменить.
class LayerContextMenu extends ConsumerWidget {
  const LayerContextMenu({super.key, required this.sourceId});

  /// Вместо id источника — базовая карта.
  static const String baseId = '';

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black12,
        builder: (_) => LayerContextMenu(sourceId: sourceId),
      );

  bool get _isBase => sourceId == baseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapLayersProvider);
    final look = ref.watch(layerLooksProvider)[sourceId] ?? const LayerLook();
    final notifier = ref.read(mapLayersProvider.notifier);
    final providers = ref.watch(catalogProvider).value ?? const [];
    final realId = _isBase ? (state.baseSourceId ?? LayersPanel.defaultBaseId) : sourceId;
    final name = catalogIndex(providers)[realId]?.source.name ?? realId;
    final ids = state.overlays.map((l) => l.sourceId).toList(); // снизу вверх
    final onMap = ids.contains(sourceId);
    final isTop = onMap && ids.last == sourceId;
    final editable = !_isBase && onMap;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    /// Закрывает меню и открывает под-шторку над тем же экраном.
    void openSheet(Future<void> Function(BuildContext context) open) {
      final under = navigator.context;
      navigator.pop();
      open(under);
    }

    Future<void> removeOthers() async {
      if (_isBase) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Базовая карта остаётся всегда')));
        return;
      }
      if (!await showConfirmDialog(context, title: 'Убрать остальные слои?')) return;
      navigator.pop();
      for (final id in ids.where((id) => id != sourceId)) {
        await notifier.removeOverlay(id);
      }
    }

    Future<void> toggleForceRefresh() async {
      final on = !look.forceRefresh;
      if (on && !await ForceRefreshDialog.show(context)) return;
      debugPrint('Force refresh toggled: $realId → $on');
      await notifier.setLook(sourceId, look.copyWith(forceRefresh: on));
    }

    return SheetMenu(
      title: name,
      children: [
        SheetMenuItem(
          key: const Key('layer_menu_details'),
          icon: Icons.info_outline,
          color: SheetMenuColors.accent,
          label: 'Детали',
          onTap: () => openSheet((c) => LayerDetailsSheet.show(c, realId)),
        ),
        SheetMenuItem(
          key: const Key('layer_menu_compare'),
          icon: Icons.compare,
          color: SheetMenuColors.accent,
          label: 'Сравнить...',
          onTap: () {
            debugPrint('Compare requested: $realId');
            navigator.pop();
          },
        ),
        SheetMenuItem(
          key: const Key('layer_menu_force_refresh'),
          icon: Icons.refresh,
          color: SheetMenuColors.accent,
          label: 'Принудительное обновление сохранённых фрагментов карты (только эта сессия)',
          onTap: editable ? toggleForceRefresh : null,
          trailing: Icon(
            look.forceRefresh ? Icons.check_box : Icons.check_box_outline_blank,
            color: editable ? SheetMenuColors.accent : SheetMenuColors.disabled,
          ),
        ),
        const SheetMenuSection('Упорядочить'),
        SheetMenuItem(
          key: const Key('layer_menu_remove'),
          icon: Icons.close,
          color: SheetMenuColors.accent,
          label: 'Убрать',
          onTap: editable
              ? () {
                  navigator.pop();
                  runLayerChange(context, () => notifier.removeOverlay(sourceId));
                }
              : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_remove_others'),
          icon: Icons.layers_clear,
          color: SheetMenuColors.accent,
          label: 'Убрать остальные',
          onTap: _isBase || (onMap && ids.length > 1) ? removeOthers : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_move_up'),
          icon: Icons.arrow_upward,
          color: SheetMenuColors.accent,
          label: 'Переместить вверх',
          onTap: editable && !isTop
              ? () {
                  final order = List.of(ids);
                  final i = order.indexOf(sourceId);
                  order
                    ..removeAt(i)
                    ..insert(i + 1, sourceId);
                  runLayerChange(context, () => notifier.reorderOverlays(order));
                }
              : null,
        ),
        const SheetMenuSection('Изменить'),
        const Padding(
          key: Key('layer_menu_info'),
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: SheetMenuColors.info),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Для сохранения изменений создайте/обновите избранную карту или набор карт.',
                  style: TextStyle(fontSize: 13, color: SheetMenuColors.info),
                ),
              ),
            ],
          ),
        ),
        SheetMenuItem(
          key: const Key('layer_menu_opacity'),
          icon: Icons.layers_outlined,
          color: SheetMenuColors.edit,
          label: 'Непрозрачность',
          onTap: editable ? () => openSheet((c) => LayerOpacitySheet.show(c, sourceId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_color'),
          icon: Icons.palette_outlined,
          color: SheetMenuColors.edit,
          label: 'Изменить цвет',
          onTap: editable ? () => openSheet((c) => LayerColorSheet.show(c, sourceId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_erase'),
          icon: Icons.colorize_outlined,
          color: SheetMenuColors.edit,
          label: 'Удалить цвет',
          onTap: editable ? () => openSheet((c) => LayerEraseColorSheet.show(c, sourceId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_blending'),
          icon: Icons.opacity,
          color: SheetMenuColors.edit,
          label: 'Режим смешивания слоёв',
          onTap: editable ? () => openSheet((c) => LayerBlendingSheet.show(c, sourceId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_invert'),
          icon: Icons.invert_colors,
          color: SheetMenuColors.edit,
          label: 'Инверсия цветов',
          onTap: editable
              ? () => runLayerChange(
                    context,
                    () => notifier.setLook(sourceId, look.copyWith(color: look.color.copyWith(inverted: !look.color.inverted))),
                  )
              : null,
          trailing: Icon(
            look.color.inverted ? Icons.check_box : Icons.check_box_outline_blank,
            color: editable ? SheetMenuColors.edit : SheetMenuColors.disabled,
          ),
        ),
        SheetMenuCancel(buttonKey: const Key('layer_menu_cancel'), onPressed: () => navigator.pop()),
      ],
    );
  }
}
