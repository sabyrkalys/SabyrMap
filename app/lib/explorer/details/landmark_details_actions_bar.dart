import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Панель под шапкой: ⋮, «ЦЕНТРИРОВАТЬ» (у объектов с координатами) и
/// показ на карте.
class LandmarkDetailsActionsBar extends StatelessWidget {
  const LandmarkDetailsActionsBar({
    super.key,
    required this.onMore,
    required this.onToggleDisplay,
    required this.displayed,
    this.onCenter,
  });

  final VoidCallback onMore;
  final VoidCallback onToggleDisplay;
  final bool displayed;

  /// null — кнопки «ЦЕНТРИРОВАТЬ» нет.
  final VoidCallback? onCenter;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('details_actions'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
    ),
    child: Row(
      children: [
        IconButton(key: const Key('details_more'), icon: const Icon(Icons.more_vert), onPressed: onMore),
        const Spacer(),
        if (onCenter != null) ...[
          TextButton(
            key: const Key('details_center'),
            onPressed: onCenter,
            style: TextButton.styleFrom(foregroundColor: SheetMenuColors.text),
            child: const Text('ЦЕНТРИРОВАТЬ', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
        ],
        IconButton(
          key: const Key('details_visibility'),
          tooltip: displayed ? 'Скрыть с карты' : 'Показать на карте',
          icon: Icon(displayed ? Icons.visibility : Icons.visibility_outlined),
          color: displayed ? SheetMenuColors.accent : null,
          onPressed: onToggleDisplay,
        ),
      ],
    ),
  );
}
