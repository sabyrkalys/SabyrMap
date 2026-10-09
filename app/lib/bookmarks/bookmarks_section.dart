import 'package:flutter/material.dart';

import '../map/screens/available_maps/side_drawer.dart';
import 'bookmark.dart';
import 'bookmark_context_menu.dart';
import 'bookmark_controller.dart';
import 'bookmark_tile.dart';

/// Раздел «ЗАКЛАДКИ» боковой панели. Без закладок не рисует ничего.
///
/// Decision: заголовок — как у остальных разделов панели (оформление
/// «Доступных карт»), а не отдельным серым стилем.
class BookmarksSection extends StatelessWidget {
  const BookmarksSection({super.key, required this.controller, required this.onOpen});

  final BookmarkController controller;
  final ValueChanged<Bookmark> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final bookmarks = controller.bookmarks;
      if (bookmarks.isEmpty) return const SizedBox.shrink();
      return Column(
        key: const Key('bookmarks_section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SideDrawerHeader('ЗАКЛАДКИ'),
          for (final b in bookmarks)
            BookmarkTile(
              bookmark: b,
              onTap: () => onOpen(b),
              onLongPress: () => BookmarkContextMenu.show(context, b, controller),
            ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
