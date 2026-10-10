import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'sheet_menu.dart';

/// Карточка метки в режиме «Предварительный просмотр»: значок типа в
/// сером квадрате 48, имя, подпись и ⋮; в режиме выбора — флажок.
class LandmarkItemCard extends StatelessWidget {
  const LandmarkItemCard({
    super.key,
    required this.path,
    required this.icon,
    required this.iconColor,
    required this.displayName,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.selecting = false,
    this.selected = false,
  });

  final String path;
  final IconData icon;
  final Color iconColor;
  final String displayName;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;
  final bool selecting;
  final bool selected;

  /// Ключ карточки по имени файла.
  static Key keyFor(String path) => Key('item_card_${p.basename(path)}');

  /// Ключ ⋮ карточки.
  static Key menuKeyFor(String path) => Key('item_card_menu_${p.basename(path)}');

  @override
  Widget build(BuildContext context) => InkWell(
    key: keyFor(path),
    onTap: onTap,
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 24, color: iconColor),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: SheetMenuColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SheetMenuColors.secondary),
                ),
              ],
            ),
          ),
          if (selecting)
            Checkbox(value: selected, onChanged: (_) => onTap())
          else
            IconButton(key: menuKeyFor(path), icon: const Icon(Icons.more_vert), onPressed: onMenu),
        ],
      ),
    ),
  );
}
