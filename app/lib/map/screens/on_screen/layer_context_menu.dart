import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialogs/confirm_dialog.dart';
import '../../../explorer/sheet_menu.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/layer_look.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';
import '../compare/compare_mode_screen.dart';
import '../compare/compare_select_dialog.dart';
import '../layer_details/layer_details_screen.dart';
import '../layer_look/layer_color_screen.dart';
import '../layers_panel.dart';
import 'force_refresh_dialog.dart';
import 'layer_opacity_sheet.dart';

/// Меню слоя «Карт на экране»: детали, порядок и вид слоя. Для базовой
/// карты ([baseId]) доступны только детали: её не убрать и не изменить.
class LayerContextMenu extends ConsumerWidget {
  const LayerContextMenu({super.key, required this.sourceId, this.fromPanel = false});

  /// Вместо id источника — базовая карта.
  static const String baseId = '';

  final String sourceId;

  /// Открыто из «Карт на экране»: экраны непрозрачности и цвета прячут
  /// панель, чтобы карта была видна, и возвращают её после.
  final bool fromPanel;

  static Future<void> show(BuildContext context, String sourceId, {bool fromPanel = false}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black12,
        builder: (_) => LayerContextMenu(sourceId: sourceId, fromPanel: fromPanel),
      );

  bool get _isBase => sourceId == baseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapLayersProvider);
    // Вид выбранной карты хранится под своим ключом, как у слоёв — под id.
    final lookId = sourceId == baseId ? MapStateNotifier.mapKey : sourceId;
    final look = ref.watch(layerLooksProvider)[lookId] ?? const LayerLook();
    final notifier = ref.read(mapLayersProvider.notifier);
    final providers = ref.watch(catalogProvider).value ?? const [];
    final realId = _isBase ? (state.baseSourceId ?? LayersPanel.defaultBaseId) : sourceId;
    // Карта убрана — в строке карты «Нет карты».
    final hasMap = (state.baseSourceId ?? LayersPanel.defaultBaseId) != LayerManager.noMapId;
    final noMap = _isBase && !hasMap;
    final name = layerName(providers, realId);
    final ids = state.overlays.map((l) => l.sourceId).toList(); // снизу вверх
    final onMap = ids.contains(sourceId);
    // Перемещаются слои и выбранная карта (общий список сверху вниз);
    // ортофотопланы и базовая карта стоят на местах.
    final stack = notifier.stack;
    final stackId = _isBase ? MapStateNotifier.mapKey : sourceId;
    final movable = stack.contains(stackId) && stack.length > 1;
    final isTop = movable && stack.first == stackId;
    // Ортофотопланы: только вид (непрозрачность, цвет); убираются кнопкой.
    final isOrthophotos = sourceId == MapStateNotifier.orthophotosKey;
    // Встроенная карта мира: только непрозрачность.
    final isWorld = sourceId == MapStateNotifier.worldKey;
    final editable = !_isBase && onMap;
    final lookEditable = editable || isOrthophotos || (_isBase && hasMap);
    final navigator = Navigator.of(context);

    /// Закрывает меню и открывает под-шторку над тем же экраном.
    void openSheet(Future<void> Function(BuildContext context) open) {
      final under = navigator.context;
      navigator.pop();
      open(under);
    }

    /// Как [openSheet], но на время экрана прячет «Карты на экране».
    Future<void> openOverMap(Future<void> Function(BuildContext context) open) async {
      final under = navigator.context;
      navigator.pop();
      if (!fromPanel) return open(under);
      navigator.pop();
      await open(under);
      if (under.mounted) await LayersPanel.show(under);
    }

    /// У слоя — убрать другие слои, у карты — все слои.
    Future<void> removeOthers() async {
      if (!await showConfirmDialog(context, title: 'Убрать остальные слои?')) return;
      navigator.pop();
      for (final id in ids.where((id) => id != sourceId)) {
        await notifier.removeOverlay(id);
      }
    }

    /// Выбор слоёв, затем режим сравнения поверх главной карты: шторки
    /// и экраны над ней закрываются.
    Future<void> startCompare() async {
      final container = ProviderScope.containerOf(context, listen: false);
      final under = navigator.context;
      navigator.pop();
      final ids = await CompareSelectDialog.show(under, sourceId);
      if (ids == null || !under.mounted) return;
      Navigator.of(under).popUntil((route) => route.isFirst);
      container.read(compareRequestProvider.notifier).start(ids);
    }

    Future<void> toggleForceRefresh() async {
      final on = !look.forceRefresh;
      if (on && !await ForceRefreshDialog.show(context)) return;
      await notifier.setLook(lookId, look.copyWith(forceRefresh: on));
      if (on) await notifier.refreshTiles();
    }

    return SheetMenu(
      title: name,
      children: [
        SheetMenuItem(
          key: const Key('layer_menu_details'),
          icon: Icons.info_outline,
          color: SheetMenuColors.accent,
          label: 'Детали',
          onTap: noMap ? null : () => openSheet((c) => LayerDetailsScreen.show(c, realId, layerMenuId: sourceId)),
        ),
        SheetMenuItem(
          key: const Key('layer_menu_compare'),
          icon: Icons.compare,
          color: SheetMenuColors.accent,
          label: 'Сравнить...',
          // Всегда есть с чем сравнить: хотя бы с «Базовой картой».
          // Сравнивают слои и карту между собой; одной карте сравнивать не с чем.
          onTap: movable ? startCompare : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_force_refresh'),
          icon: Icons.refresh,
          color: SheetMenuColors.accent,
          label: 'Принудительное обновление сохранённых фрагментов карты (только эта сессия)',
          // Файлы на телефоне (ортофотопланы, базовая карта) обновлять неоткуда.
          onTap: editable || (_isBase && hasMap) ? toggleForceRefresh : null,
          trailing: Icon(
            look.forceRefresh ? Icons.check_box : Icons.check_box_outline_blank,
            color: editable || (_isBase && hasMap) ? SheetMenuColors.accent : SheetMenuColors.disabled,
          ),
        ),
        const SheetMenuSection('Упорядочить'),
        SheetMenuItem(
          key: const Key('layer_menu_remove'),
          icon: Icons.close,
          color: SheetMenuColors.accent,
          label: 'Убрать',
          onTap: editable || (_isBase && !noMap)
              ? () {
                  navigator.pop();
                  runLayerChange(
                    context,
                    () async => _isBase ? await notifier.removeMap() : await notifier.removeOverlay(sourceId),
                  );
                }
              : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_remove_others'),
          icon: Icons.layers_clear,
          color: SheetMenuColors.accent,
          label: 'Убрать остальные',
          // Есть что убирать: у карты — хоть один слой, у слоя — другие слои.
          onTap: (_isBase && hasMap && ids.isNotEmpty) || (onMap && ids.length > 1) ? removeOthers : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_move_up'),
          // Верхний слой — только вниз, остальные — вверх.
          icon: isTop ? Icons.arrow_downward : Icons.arrow_upward,
          color: SheetMenuColors.accent,
          label: isTop ? 'Переместить вниз' : 'Переместить вверх',
          onTap: movable
              ? () {
                  final order = List.of(stack);
                  final i = order.indexOf(stackId);
                  order
                    ..removeAt(i)
                    ..insert(isTop ? i + 1 : i - 1, stackId);
                  runLayerChange(context, () => notifier.reorderStack(order));
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
          onTap: lookEditable || isWorld ? () => openOverMap((c) => LayerOpacitySheet.show(c, lookId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_color'),
          icon: Icons.palette_outlined,
          color: SheetMenuColors.edit,
          label: 'Изменить цвет',
          onTap: lookEditable ? () => openOverMap((c) => LayerColorScreen.show(c, lookId)) : null,
        ),
        SheetMenuItem(
          key: const Key('layer_menu_invert'),
          icon: Icons.invert_colors,
          color: SheetMenuColors.edit,
          label: 'Инверсия цветов',
          onTap: lookEditable
              ? () => runLayerChange(
                  context,
                  () => notifier.setLook(
                    lookId,
                    look.copyWith(color: look.color.copyWith(inverted: !look.color.inverted)),
                  ),
                )
              : null,
          trailing: Icon(
            look.color.inverted ? Icons.check_box : Icons.check_box_outline_blank,
            color: lookEditable ? SheetMenuColors.edit : SheetMenuColors.disabled,
          ),
        ),
        SheetMenuCancel(buttonKey: const Key('layer_menu_cancel'), onPressed: () => navigator.pop()),
      ],
    );
  }
}
