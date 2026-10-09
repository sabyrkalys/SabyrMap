import 'package:flutter/material.dart';

import 'bookmark.dart';
import 'bookmark_actions.dart';
import 'bookmark_controller.dart';

/// Меню закладки по долгому нажатию: её имя, «Удалить», «ОТМЕНА».
class BookmarkContextMenu extends StatelessWidget {
  const BookmarkContextMenu({super.key, required this.bookmark, required this.controller});

  final Bookmark bookmark;
  final BookmarkController controller;

  static Future<void> show(BuildContext context, Bookmark bookmark, BookmarkController controller) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => BookmarkContextMenu(bookmark: bookmark, controller: controller),
      );

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('bookmark_menu'),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                bookmark.name,
                key: const Key('bookmark_menu_title'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
              ),
            ),
            InkWell(
              key: const Key('bookmark_menu_remove'),
              onTap: () => BookmarkActions.delete(context, bookmark, controller),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(width: 32, child: Icon(Icons.delete, size: 24, color: Color(0xFFD32F2F))),
                    SizedBox(width: 16),
                    Text('Удалить', style: TextStyle(fontSize: 16, color: Color(0xFF212121))),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('bookmark_menu_cancel'),
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                  child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
