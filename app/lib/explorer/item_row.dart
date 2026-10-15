import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter/material.dart';

/// Строка файла метки: иконка по типу в цвете метки, имя, подпись; в
/// режиме выбора — флажок.
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

  /// Иконки — как на листе «Новая метка».
  static IconData iconFor(LandmarkType type) => switch (type) {
    LandmarkType.waypoint => Icons.location_on_sharp,
    LandmarkType.set => Icons.share_location_sharp,
    LandmarkType.route => Icons.route_sharp,
    LandmarkType.track => Icons.polyline_sharp,
    LandmarkType.area => Icons.pentagon_outlined,
    LandmarkType.ldkFile => Icons.description_outlined,
    LandmarkType.circle => Icons.circle_outlined,
    LandmarkType.text => Icons.text_fields,
  };

  static String kindOf(LandmarkType type) => switch (type) {
    LandmarkType.waypoint => 'Путевая точка',
    LandmarkType.set => 'Набор точек',
    LandmarkType.route => 'Маршрут',
    LandmarkType.track => 'Путь',
    LandmarkType.area => 'Область',
    LandmarkType.ldkFile => 'Файл меток',
    LandmarkType.circle => 'Круг',
    LandmarkType.text => 'Текст',
  };

  /// Подпись: вид, длина или площадь, дата.
  static String subtitleFor(LandmarkItem item) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(date.day)}.${two(date.month)}.${date.year}';
    final length = item.lengthMeters;
    final area = item.areaSquareMeters;
    final kind = kindOf(item.type);
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
  Widget build(BuildContext context) => ListTile(
    key: Key('item_row_${item.name}'),
    dense: dense,
    leading: selecting
        ? Checkbox(value: selected, onChanged: (_) => onTap())
        : Icon(iconFor(item.type), color: Color(item.displayColor | 0xFF000000)),
    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(subtitleFor(item), maxLines: 1),
    selected: selected,
    onTap: onTap,
    onLongPress: onLongPress,
  );
}
