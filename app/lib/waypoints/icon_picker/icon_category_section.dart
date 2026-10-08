import 'package:flutter/material.dart';

import 'icon_item.dart';
import 'marker_icon.dart';

/// A category of the «Иконка» sheet: a header with a chevron that turns
/// over, and the category's icons folding out under it.
class IconCategorySection extends StatelessWidget {
  const IconCategorySection({
    super.key,
    required this.category,
    required this.isExpanded,
    required this.onToggle,
    required this.onSelected,
    this.currentIconId,
  });

  final IconCategory category;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<MarkerIcon> onSelected;
  final String? currentIconId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('icon_category_${category.id}'),
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFD0D7DE))),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  key: Key('icon_category_chevron_${category.id}'),
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_sharp, size: 20, color: Color(0xFF333333)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    category.title,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF212121), letterSpacing: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final icon in category.icons)
                      IconItem(icon: icon, selected: icon.id == currentIconId, onTap: () => onSelected(icon)),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
