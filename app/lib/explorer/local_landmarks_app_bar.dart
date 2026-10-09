import 'package:app/landmarks/explorer/explorer_view_mode.dart';
import 'package:flutter/material.dart';

import 'explorer_style.dart';
import 'explorer_view_mode_switch.dart';

/// Пункты меню шапки.
enum ExplorerMenuAction { sort, filter, statistics, selectAll, viewMode }

/// Шапка: меню разделов, «Локальные метки» и текущая папка, закрыть, меню.
class LocalLandmarksAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LocalLandmarksAppBar({
    super.key,
    required this.subtitle,
    required this.viewMode,
    required this.onMenuAction,
  });

  final String subtitle;
  final ExplorerViewMode viewMode;
  final ValueChanged<ExplorerMenuAction> onMenuAction;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: ExplorerStyle.background,
    surfaceTintColor: Colors.transparent,
    foregroundColor: ExplorerStyle.icon,
    shape: const Border(bottom: BorderSide(color: ExplorerStyle.divider)),
    leading: Builder(
      builder: (context) => IconButton(
        key: const Key('explorer_menu_button'),
        icon: const Icon(Icons.menu),
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
    ),
    titleSpacing: 0,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Локальные метки', style: ExplorerStyle.title),
        Text(
          subtitle,
          key: const Key('explorer_subtitle'),
          style: ExplorerStyle.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
    actions: [
      IconButton(
        key: const Key('explorer_close'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      PopupMenuButton<ExplorerMenuAction>(
        key: const Key('explorer_overflow'),
        onSelected: onMenuAction,
        itemBuilder: (_) => [
          const PopupMenuItem(value: ExplorerMenuAction.sort, child: Text('Сортировка…')),
          const PopupMenuItem(value: ExplorerMenuAction.filter, child: Text('Фильтры…')),
          const PopupMenuItem(value: ExplorerMenuAction.statistics, child: Text('Статистика…')),
          const PopupMenuItem(value: ExplorerMenuAction.selectAll, child: Text('Выбрать всё')),
          PopupMenuItem(value: ExplorerMenuAction.viewMode, child: Text(ExplorerViewModeSwitch.labelFor(viewMode))),
        ],
      ),
    ],
  );
}
