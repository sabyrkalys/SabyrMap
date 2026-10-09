import 'package:flutter/material.dart';

import '../bookmark.dart';

/// «Удалить «имя»» / «Вы уверены?» — НЕТ (false) или ДА (true).
class BookmarkDeleteConfirmDialog extends StatelessWidget {
  const BookmarkDeleteConfirmDialog({super.key, required this.bookmark});

  final Bookmark bookmark;

  static const Color red = Color(0xFFD32F2F);
  static const Color accent = Color(0xFF00A38E);

  static Future<bool?> show(BuildContext context, Bookmark bookmark) => showDialog<bool>(
    context: context,
    builder: (_) => BookmarkDeleteConfirmDialog(bookmark: bookmark),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const buttonStyle = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5);
    return AlertDialog(
      key: const Key('bookmark_delete_dialog'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: EdgeInsets.symmetric(horizontal: width * 0.075, vertical: 24),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      content: SizedBox(
        width: width * 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 36, child: Icon(Icons.delete, size: 28, color: red)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Удалить «${bookmark.name}»',
                    key: const Key('bookmark_delete_title'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Вы уверены?', style: TextStyle(fontSize: 16, color: Color(0xFF212121))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('bookmark_delete_no'),
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: const Text('НЕТ', style: buttonStyle),
                ),
                const SizedBox(width: 16),
                TextButton(
                  key: const Key('bookmark_delete_yes'),
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: const Text('ДА', style: buttonStyle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
