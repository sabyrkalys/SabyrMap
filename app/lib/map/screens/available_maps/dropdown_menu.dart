import 'package:flutter/material.dart';

enum MapsMenuAction {
  filter('Фильтр', Icons.filter_list),
  settings('Настройки', Icons.settings_outlined),
  help('Помощь', Icons.help_outline);

  const MapsMenuAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Menu under the top bar's ⋮. A tap outside it calls [onDismiss].
class MapsDropdownMenu extends StatelessWidget {
  const MapsDropdownMenu({super.key, required this.isOpen, required this.onSelected, required this.onDismiss});

  final bool isOpen;
  final ValueChanged<MapsMenuAction> onSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(key: const Key('dropdown_scrim'), behavior: HitTestBehavior.opaque, onTap: onDismiss),
        ),
        Positioned(
          top: 4,
          right: 8,
          child: Material(
            key: const Key('maps_dropdown'),
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in MapsMenuAction.values)
                    InkWell(
                      key: Key('dropdown_${action.name}'),
                      onTap: () => onSelected(action),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                        child: Row(
                          children: [Icon(action.icon, size: 20), const SizedBox(width: 12), Text(action.label)],
                        ),
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
