import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../app/landmark_services_provider.dart';
import '../../dialogs/confirm_dialog.dart';
import '../../map/map_target.dart';
import '../../waypoints/waypoints_controller.dart';
import '../descriptors/context_menu_action.dart';
import '../descriptors/menu_env.dart';
import '../details/landmark_details_screen.dart';
import '../dialogs/color_picker_sheet.dart';
import '../dialogs/landmark_properties_dialog.dart';
import '../export/landmark_export_flow.dart';
import '../ldk/ldk_rename_dialog.dart';
import 'item_actions.dart';
import 'item_hooks.dart';

/// Цвета иконок меню, ARGB.
abstract final class MenuColors {
  static const int base = 0xFF00A38E;
  static const int clipboard = 0xFF9C27B0;
  static const int edit = 0xFFD32F2F;
  static const int select = 0xFF212121;
}

/// Пункты меню элемента: из них дескрипторы собирают меню своих типов.
/// [BuildContext] действия — экран, с которого открыто меню.
abstract final class ItemMenuEntries {
  static LandmarkServices services(BuildContext context) =>
      ProviderScope.containerOf(context, listen: false).read(landmarkServicesProvider);

  static void say(BuildContext context, String? text) {
    if (text != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Файлы изменились: перечитать список и точки на карте.
  static Future<void> changed(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(landmarkServicesProvider).explorerController.refresh();
    await container.read(waypointsControllerProvider.notifier).loadWaypoints();
  }

  static Future<void> _open(BuildContext context, String path) async {
    final open = ItemHooks.maybeOf(context)?.onOpen;
    if (open != null) return open(path);
    await LandmarkDetailsScreen.open(context, path);
  }

  static ContextMenuAction details(LandmarkItem item) => ContextMenuAction(
    id: 'details',
    label: 'Детали',
    icon: Icons.info_outline,
    iconColor: MenuColors.base,
    onTap: (c) => _open(c, item.path),
  );

  static ContextMenuAction open(LandmarkItem item) => ContextMenuAction(
    id: 'open',
    label: 'Открыть',
    icon: Icons.subdirectory_arrow_right,
    iconColor: MenuColors.base,
    onTap: (c) => _open(c, item.path),
  );

  static ContextMenuAction display(LandmarkItem item) => ContextMenuAction(
    id: 'display',
    label: 'Показать',
    icon: Icons.visibility_outlined,
    iconColor: MenuColors.base,
    labelResolver: (env) => (env as MenuEnv).services.displayRegistry.isDisplayed(item.path) ? 'Скрыть' : 'Показать',
    onTap: (c) async =>
        say(c, ItemActions.toggleDisplay(services(c), item.path) ? 'Показано на карте' : 'Скрыто с карты'),
  );

  static ContextMenuAction setTarget(LandmarkItem item) => ContextMenuAction(
    id: 'target',
    label: 'Задать целью',
    icon: Icons.flag_outlined,
    iconColor: MenuColors.base,
    onTap: (c) async {
      final container = ProviderScope.containerOf(c, listen: false);
      try {
        final at = await ItemActions.setTarget(services(c), item.path);
        container.read(mapTargetProvider.notifier).setAt(LatLng(at.latitude, at.longitude));
        if (c.mounted) say(c, 'Цель: ${item.name}');
      } on Exception catch (e) {
        if (c.mounted) say(c, 'Не удалось задать цель: $e');
      }
    },
  );

  static ContextMenuAction share(LandmarkItem item) => ContextMenuAction(
    id: 'share',
    label: 'Поделиться',
    icon: Icons.share_outlined,
    iconColor: MenuColors.base,
    onTap: (c) async {
      final text = await ItemActions.share(services(c), item.path);
      if (c.mounted) say(c, text);
    },
  );

  static ContextMenuAction export(LandmarkItem item) => ContextMenuAction(
    id: 'export',
    label: 'Экспортировать как...',
    icon: Icons.file_download_outlined,
    iconColor: MenuColors.base,
    onTap: (c) async => LandmarkExportFlow.start(c, item.path),
  );

  static ContextMenuAction copy(LandmarkItem item) => ContextMenuAction(
    id: 'copy',
    label: 'Копировать',
    icon: Icons.copy_outlined,
    iconColor: MenuColors.clipboard,
    onTap: (c) async {
      final s = services(c);
      say(c, ItemActions.copy(s, item));
      await s.explorerController.refresh();
    },
  );

  static ContextMenuAction cut(LandmarkItem item) => ContextMenuAction(
    id: 'cut',
    label: 'Вырезать',
    icon: Icons.content_cut,
    iconColor: MenuColors.clipboard,
    onTap: (c) async {
      final s = services(c);
      say(c, ItemActions.cut(s, item));
      await s.explorerController.refresh();
    },
  );

  static ContextMenuAction select(LandmarkItem item) => ContextMenuAction(
    id: 'select',
    label: 'Выбрать',
    icon: Icons.check_box_outlined,
    iconColor: MenuColors.select,
    onTap: (c) async => ItemActions.select(services(c), item.path),
  );

  static ContextMenuAction color(LandmarkItem item) => ContextMenuAction(
    id: 'color',
    label: 'Изменить цвет',
    icon: Icons.palette_outlined,
    iconColor: MenuColors.edit,
    onTap: (c) async {
      final color = await ColorPickerSheet.show(c, current: item.colorValue);
      if (color == null || !c.mounted) return;
      final text = await ItemActions.setColor(services(c), item.path, color);
      if (!c.mounted) return;
      say(c, text);
      await changed(c);
    },
  );

  static ContextMenuAction properties(LandmarkItem item) => ContextMenuAction(
    id: 'properties',
    label: 'Изменить свойства',
    icon: Icons.edit_outlined,
    iconColor: MenuColors.edit,
    onTap: (c) async {
      final s = services(c);
      LandmarkFile? file;
      try {
        file = await s.repository.load(item.path);
      } on Exception {
        file = null;
      }
      if (!c.mounted) return;
      final props = await LandmarkPropertiesDialog.show(
        c,
        initial: file == null ? LandmarkProperties(name: item.name) : ItemActions.propertiesOf(file, item.path),
      );
      if (props == null || !c.mounted) return;
      final text = await ItemActions.updateProperties(s, item.path, props);
      if (!c.mounted) return;
      say(c, text);
      await changed(c);
    },
  );

  static ContextMenuAction delete(LandmarkItem item) => ContextMenuAction(
    id: 'delete',
    label: 'Удалить',
    icon: Icons.delete_outline,
    iconColor: MenuColors.edit,
    onTap: (c) async {
      final hooks = ItemHooks.maybeOf(c);
      final ok = await showConfirmDialog(
        c,
        title: 'Удалить «${item.name}»?',
        message: 'Файл будет удалён без возможности восстановления.',
        confirmLabel: 'Удалить',
        cancelLabel: 'Отмена',
      );
      if (!ok || !c.mounted) return;
      final text = await ItemActions.delete(services(c), item.path);
      if (c.mounted) {
        say(c, text);
        await changed(c);
      }
      hooks?.onDeleted?.call();
    },
  );

  static ContextMenuAction rename(LandmarkItem item) => ContextMenuAction(
    id: 'rename',
    label: 'Переименовать',
    icon: Icons.drive_file_rename_outline,
    iconColor: MenuColors.edit,
    onTap: (c) async {
      final hooks = ItemHooks.maybeOf(c);
      final name = await LdkRenameDialog.show(c, item.name);
      if (name == null || !c.mounted) return;
      final result = await ItemActions.rename(services(c), item.path, name);
      if (result == null || !c.mounted) return;
      say(c, result.message);
      // Сначала экран узнаёт новый путь, затем список перечитывается.
      if (result.path case final renamed?) hooks?.onRenamed?.call(renamed);
      if (c.mounted) await changed(c);
    },
  );

  static ContextMenuAction reverseRoute(LandmarkItem item) => ContextMenuAction(
    id: 'reverse',
    label: 'Реверс порядка',
    icon: Icons.swap_vert,
    iconColor: MenuColors.base,
    onTap: (c) async {
      final text = await ItemActions.reverseRoute(services(c), item.path);
      if (!c.mounted) return;
      say(c, text);
      await changed(c);
    },
  );

  static ContextMenuAction toggleClosed(LandmarkItem item) => ContextMenuAction(
    id: 'closed',
    label: 'Замкнуть контур',
    icon: Icons.pentagon_outlined,
    iconColor: MenuColors.edit,
    labelResolver: (env) => switch ((env as MenuEnv).object) {
      final AreaObject area when CompositeCalculator.isClosed(area) => 'Разомкнуть контур',
      _ => 'Замкнуть контур',
    },
    onTap: (c) async {
      try {
        final closed = await ItemActions.toggleClosed(services(c), item.path);
        if (!c.mounted) return;
        say(c, closed ? 'Контур замкнут' : 'Контур разомкнут');
        await changed(c);
      } on Exception catch (e) {
        if (c.mounted) say(c, 'Не удалось изменить контур: $e');
      }
    },
  );

  /// Пункт без реализации: запись в лог и сообщение «пока недоступна».
  static ContextMenuAction stub(
    LandmarkItem item, {
    required String id,
    required String label,
    required IconData icon,
    int iconColor = MenuColors.base,
  }) => ContextMenuAction(
    id: id,
    label: label,
    icon: icon,
    iconColor: iconColor,
    onTap: (c) async => say(c, ItemActions.stub(label, item.path)),
  );
}
