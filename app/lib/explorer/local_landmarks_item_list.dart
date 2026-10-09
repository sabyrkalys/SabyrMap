import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:flutter/material.dart';

import 'item_row.dart';

/// Файлы меток текущей папки.
class LocalLandmarksItemList extends StatelessWidget {
  const LocalLandmarksItemList({
    super.key,
    required this.items,
    required this.selecting,
    required this.isSelected,
    required this.dense,
    required this.onTap,
    required this.onLongPress,
  });

  final List<ExplorerItemNode> items;
  final bool selecting;
  final bool Function(String path) isSelected;
  final bool dense;
  final ValueChanged<LandmarkItem> onTap;
  final ValueChanged<LandmarkItem> onLongPress;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final node in items)
        ItemRow(
          item: node.item,
          selecting: selecting,
          selected: isSelected(node.path),
          dense: dense,
          onTap: () => onTap(node.item),
          onLongPress: () => onLongPress(node.item),
        ),
    ],
  );
}
