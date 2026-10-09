import 'package:flutter/material.dart';

import 'bookmark.dart';
import 'bookmark_controller.dart';
import 'dialogs/bookmark_delete_confirm_dialog.dart';

/// Действия над закладкой из её меню.
abstract final class BookmarkActions {
  /// Спрашивает «Вы уверены?»; «ДА» — удаляет, закрывает меню и сообщает;
  /// «НЕТ» — меню остаётся открытым.
  static Future<void> delete(BuildContext menuContext, Bookmark bookmark, BookmarkController controller) async {
    final messenger = ScaffoldMessenger.of(menuContext);
    final navigator = Navigator.of(menuContext);
    final yes = await BookmarkDeleteConfirmDialog.show(menuContext, bookmark);
    if (yes != true) return;
    await controller.remove(bookmark.id);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Закладка удалена')));
  }
}
