import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Выбор цвета метки из палитры; результат — ARGB или null («ОТМЕНА»).
class ColorPickerSheet extends StatelessWidget {
  const ColorPickerSheet({super.key, this.current});

  /// Текущий цвет — отмечается галочкой.
  final int? current;

  /// Палитра: насыщенные цвета, хорошо видимые на карте и спутнике.
  static const List<int> palette = [
    0xFFEE1111,
    0xFFE65100,
    0xFFFFC107,
    0xFF8BC34A,
    0xFF2E7D32,
    0xFF00A38E,
    0xFF00BCD4,
    0xFF1565C0,
    0xFF3F51B5,
    0xFF9C27B0,
    0xFFE91E63,
    0xFF795548,
    0xFF607D8B,
    0xFF212121,
    0xFFFFFFFF,
  ];

  static Future<int?> show(BuildContext context, {int? current}) => showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ColorPickerSheet(current: current),
  );

  @override
  Widget build(BuildContext context) => SheetMenu(
    key: const Key('color_picker_sheet'),
    title: 'Цвет',
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final color in palette)
            InkWell(
              key: Key('color_${color.toRadixString(16)}'),
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context, color),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBDBDBD)),
                ),
                child: current == color
                    ? Icon(Icons.check, color: color == 0xFFFFFFFF ? SheetMenuColors.text : Colors.white)
                    : null,
              ),
            ),
        ],
      ),
      SheetMenuCancel(buttonKey: const Key('color_picker_cancel'), onPressed: () => Navigator.pop(context)),
    ],
  );
}
