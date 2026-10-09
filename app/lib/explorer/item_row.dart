import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';

import 'explorer_style.dart';

/// Строка файла метки: иконка по типу, имя, подпись; в режиме выбора —
/// флажок.
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.dense = false,
  });

  final LandmarkItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selecting;
  final bool selected;

  /// Компактный вид списка.
  final bool dense;

  static IconData iconFor(LandmarkType type) => switch (type) {
    LandmarkType.waypoint => Icons.place_outlined,
    LandmarkType.set => Icons.scatter_plot_outlined,
    LandmarkType.route => Icons.route_outlined,
    LandmarkType.track => Icons.timeline,
    LandmarkType.area => Icons.crop_square,
  };

  /// Подпись: длина/площадь для составных, иначе тип и дата.
  static String subtitleFor(LandmarkItem item) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(date.day)}.${two(date.month)}.${date.year}';
    final length = item.lengthMeters;
    final area = item.areaSquareMeters;
    final kind = switch (item.type) {
      LandmarkType.waypoint => 'Путевая точка',
      LandmarkType.set => 'Набор точек',
      LandmarkType.route => 'Маршрут',
      LandmarkType.track => 'Трек',
      LandmarkType.area => 'Область',
    };
    if (length != null && length > 0) {
      final l = length >= 1000 ? '${(length / 1000).toStringAsFixed(2)} км' : '${length.round()} м';
      return '$kind · $l · $when';
    }
    if (area != null && area > 0) {
      final a = area >= 1e6 ? '${(area / 1e6).toStringAsFixed(2)} км²' : '${area.round()} м²';
      return '$kind · $a · $when';
    }
    return '$kind · $when';
  }

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('item_row_${item.name}'),
    onTap: onTap,
    onLongPress: onLongPress,
    child: SizedBox(
      height: dense ? 52 : 64,
      child: Row(
        children: [
          const SizedBox(width: 16),
          if (selecting)
            Checkbox(value: selected, onChanged: (_) => onTap(), activeColor: ExplorerStyle.accent)
          else
            Icon(iconFor(item.type), size: 24, color: Color(item.colorValue | 0xFF000000)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: ExplorerStyle.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (!dense) Text(subtitleFor(item), style: ExplorerStyle.subtitle, maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );
}
