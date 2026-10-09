import 'package:flutter/material.dart';

import 'bookmark.dart';

/// Пункт закладки: иконка папки и имя.
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({super.key, required this.bookmark, required this.onTap, required this.onLongPress});

  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('bookmark_tile_${bookmark.name}'),
    onTap: onTap,
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 32, child: Icon(Icons.folder_outlined, size: 22, color: Color(0xFF333333))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              bookmark.name,
              style: const TextStyle(fontSize: 15, color: Color(0xFF212121)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
