import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:flutter/material.dart';

import '../../format_bytes.dart';
import '../sheet_menu.dart';
import 'ldk_item_card.dart';

/// Пункты меню секции «ФАЙЛЫ МЕТОК».
enum LdkSectionAction { create, selectAll }

/// Секция «ФАЙЛЫ МЕТОК»: заголовок с ⋮, «N элем.» и карточки `.ldk`.
/// Без файлов секция не показывается.
class LdkSection extends StatelessWidget {
  const LdkSection({
    super.key,
    required this.items,
    required this.groupName,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    required this.onSectionMenu,
    this.selecting = false,
    this.isSelected,
  });

  /// Только файлы меток; прочие типы сюда не передаются.
  final List<LandmarkItem> items;

  /// Подпись группы (папки) в карточке.
  final String groupName;
  final ValueChanged<LandmarkItem> onTap;
  final ValueChanged<LandmarkItem> onLongPress;
  final ValueChanged<LandmarkItem> onMenu;
  final VoidCallback onSectionMenu;
  final bool selecting;
  final bool Function(String path)? isSelected;

  /// Меню секции; null — закрыто без выбора.
  static Future<LdkSectionAction?> showMenu(BuildContext context) =>
      showModalBottomSheet<LdkSectionAction>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SheetMenu(
          key: const Key('ldk_section_sheet'),
          title: 'Файлы меток',
          children: [
            SheetMenuItem(
              key: const Key('ldk_section_create'),
              icon: Icons.note_add_outlined,
              color: SheetMenuColors.accent,
              label: 'Новый файл меток',
              onTap: () => Navigator.pop(context, LdkSectionAction.create),
            ),
            SheetMenuItem(
              key: const Key('ldk_section_select_all'),
              icon: Icons.check_box_outlined,
              color: SheetMenuColors.text,
              label: 'Выбрать все',
              onTap: () => Navigator.pop(context, LdkSectionAction.selectAll),
            ),
            SheetMenuCancel(
              buttonKey: const Key('ldk_section_cancel'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('ldk_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              const Text(
                'ФАЙЛЫ МЕТОК',
                style: TextStyle(
                  fontSize: 12,
                  color: SheetMenuColors.secondary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('ldk_section_menu'),
                icon: const Icon(Icons.more_vert),
                onPressed: onSectionMenu,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${items.length} элем.',
            key: const Key('ldk_section_count'),
            style: const TextStyle(
              fontSize: 12,
              color: SheetMenuColors.secondary,
            ),
          ),
        ),
        for (final item in items)
          LdkItemCard(
            path: item.path,
            displayName: item.name,
            subtitle: '$groupName · ${formatBytes(item.fileSizeBytes)}',
            selecting: selecting,
            selected: isSelected?.call(item.path) ?? false,
            onTap: () => onTap(item),
            onLongPress: () => onLongPress(item),
            onMenu: () => onMenu(item),
          ),
      ],
    );
  }
}
