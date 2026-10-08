import 'package:flutter/material.dart';

/// What «ЕЩЁ...» can add to a waypoint.
enum WaypointExtra {
  color('Цвет', Icons.palette_sharp),
  style('Стиль', Icons.style_sharp),
  image('Изображение', Icons.photo_camera_sharp),
  gallery('Галерея', Icons.photo_library_sharp),
  audio('Аудио', Icons.mic_sharp),
  course('Курс', Icons.explore_sharp),
  website('Сайт', Icons.language_sharp),
  keywords('Ключевые слова', Icons.sell_sharp),
  description('Описание', Icons.notes_sharp);

  const WaypointExtra(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The «ЕЩЁ...» sheet over the «Путевая точка» dialog. Completes with the
/// chosen extra, or null on «ОТМЕНА».
Future<WaypointExtra?> showWaypointMoreSheet(BuildContext context) {
  return showModalBottomSheet<WaypointExtra>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFFF5F6F8),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('waypoint_more_sheet'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Добавить',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
              ),
            ),
            for (final extra in WaypointExtra.values)
              InkWell(
                key: Key('waypoint_more_${extra.name}'),
                onTap: () => Navigator.of(context).pop(extra),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      SizedBox(width: 32, child: Icon(extra.icon, size: 24, color: const Color(0xFF333333))),
                      const SizedBox(width: 16),
                      Text(extra.label, style: const TextStyle(fontSize: 16, color: Color(0xFF212121))),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('waypoint_more_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
