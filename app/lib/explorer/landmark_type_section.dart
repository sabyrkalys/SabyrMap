import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';

import '../format_bytes.dart';
import 'descriptors/landmark_type_descriptor.dart';
import 'item_row.dart';
import 'landmark_item_card.dart';
import 'sheet_menu.dart';

/// Секция списка с метками одного типа: заголовок с ⋮, подпись («N элем.»)
/// и элементы — строками или карточками. Без элементов не показывается.
class LandmarkTypeSection extends StatelessWidget {
  const LandmarkTypeSection({
    super.key,
    required this.descriptor,
    required this.items,
    required this.viewMode,
    required this.groupName,
    required this.onTap,
    required this.onLongPress,
    required this.onSectionMenu,
    this.dense = false,
    this.selecting = false,
    this.isSelected,
  });

  final LandmarkTypeDescriptor descriptor;

  /// Уже отсортированные элементы типа секции.
  final List<LandmarkItem> items;
  final SectionViewMode viewMode;

  /// Папка в подписи карточек файлов меток.
  final String groupName;
  final ValueChanged<LandmarkItem> onTap;

  /// Долгое нажатие и ⋮ карточки.
  final ValueChanged<LandmarkItem> onLongPress;
  final VoidCallback onSectionMenu;

  /// Компактные строки (общий вид списка).
  final bool dense;
  final bool selecting;
  final bool Function(String path)? isSelected;

  String _cardSubtitle(LandmarkItem item) => item.type == LandmarkType.ldkFile
      ? '$groupName · ${formatBytes(item.fileSizeBytes)}'
      : ItemRow.subtitleFor(item);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final ext = descriptor.type.extension;
    return Column(
      key: Key('section_$ext'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Text(
                descriptor.sectionTitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: SheetMenuColors.secondary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(key: Key('section_menu_$ext'), icon: const Icon(Icons.more_vert), onPressed: onSectionMenu),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            descriptor.subtitleFor(items),
            key: Key('section_subtitle_$ext'),
            style: const TextStyle(fontSize: 12, color: SheetMenuColors.secondary),
          ),
        ),
        for (final item in items)
          if (viewMode == SectionViewMode.preview)
            LandmarkItemCard(
              path: item.path,
              icon: ItemRow.iconFor(item.type),
              iconColor: item.type == LandmarkType.ldkFile
                  ? Color(descriptor.iconColor)
                  : Color(item.colorValue | 0xFF000000),
              displayName: item.name,
              subtitle: _cardSubtitle(item),
              selecting: selecting,
              selected: isSelected?.call(item.path) ?? false,
              onTap: () => onTap(item),
              onLongPress: () => onLongPress(item),
              onMenu: () => onLongPress(item),
            )
          else
            ItemRow(
              item: item,
              dense: dense,
              selecting: selecting,
              selected: isSelected?.call(item.path) ?? false,
              onTap: () => onTap(item),
              onLongPress: () => onLongPress(item),
            ),
      ],
    );
  }
}
