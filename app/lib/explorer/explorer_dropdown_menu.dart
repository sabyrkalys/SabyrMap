import 'package:app/landmarks/explorer/explorer_view_mode.dart';
import 'package:flutter/material.dart';

import 'explorer_view_mode_switch.dart';

/// Пункты меню «⋮».
enum ExplorerMenuAction { sort, filter, statistics, selectAll, viewMode }

/// Меню под «⋮» шапки, в оформлении меню «Доступных карт». Тап мимо —
/// [onDismiss].
class ExplorerDropdownMenu extends StatelessWidget {
  const ExplorerDropdownMenu({
    super.key,
    required this.isOpen,
    required this.viewMode,
    required this.onSelected,
    required this.onDismiss,
  });

  final bool isOpen;
  final ExplorerViewMode viewMode;
  final ValueChanged<ExplorerMenuAction> onSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();
    final items = [
      (ExplorerMenuAction.sort, Icons.sort, 'Сортировка'),
      (ExplorerMenuAction.filter, Icons.filter_list, 'Фильтр'),
      (ExplorerMenuAction.statistics, Icons.insights_outlined, 'Статистика'),
      (ExplorerMenuAction.selectAll, Icons.checklist, 'Выбрать всё'),
      (ExplorerMenuAction.viewMode, Icons.view_agenda_outlined, ExplorerViewModeSwitch.labelFor(viewMode)),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('explorer_dropdown_scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          top: 4,
          right: 8,
          child: Material(
            key: const Key('explorer_dropdown'),
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (action, icon, label) in items)
                    InkWell(
                      key: Key('explorer_menu_${action.name}'),
                      onTap: () => onSelected(action),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                        child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
