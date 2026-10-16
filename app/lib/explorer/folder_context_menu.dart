import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/landmark_services_provider.dart';
import '../dialogs/confirm_dialog.dart';
import '../format_bytes.dart';
import 'dialogs/rename_folder_dialog.dart';
import 'folder_context_actions.dart';
import 'sheet_menu.dart';

/// Меню папки по долгому нажатию: «Открыть», «Закладка», «Детали»; БУФЕР
/// ОБМЕНА — «Копировать», «Вырезать»; ИЗМЕНИТЬ — «Переименовать»,
/// «Удалить».
class FolderContextMenu extends ConsumerWidget {
  const FolderContextMenu({super.key, required this.folder});

  final ExplorerFolderNode folder;

  static const Color _text = Color(0xFF212121);
  static const Color _accent = Color(0xFF00A38E);
  static const Color _clipboard = Color(0xFF9C27B0);
  static const Color _edit = Color(0xFFD32F2F);

  /// Decision: высота — по содержимому (isScrollControlled), а не 9/16
  /// экрана: иначе «Удалить» и «ОТМЕНА» на телефоне уходят под край.
  static Future<void> show(BuildContext context, ExplorerFolderNode folder) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FolderContextMenu(folder: folder),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(landmarkServicesProvider);
    final explorer = services.explorerController;
    // Сообщения и диалоги — от экрана под шторкой: сама шторка закрывается.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final screen = navigator.context;

    void say(String? text) {
      if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
    }

    // Карта узнаёт об изменениях из индекса меток сама.
    Future<void> changed() => explorer.refresh();

    Widget item(String key, IconData icon, Color color, String label, Future<void> Function() action) => InkWell(
      key: Key('folder_menu_$key'),
      onTap: action,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 32, child: Icon(icon, size: 24, color: color)),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontSize: 16, color: _text)),
          ],
        ),
      ),
    );

    return Container(
      key: const Key('folder_context_menu'),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  folder.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _text),
                ),
              ),
              item('open', Icons.subdirectory_arrow_right, _accent, 'Открыть', () async {
                navigator.pop();
                await explorer.openFolder(folder.path);
              }),
              item('bookmark', Icons.bookmark_add_outlined, _accent, 'Закладка', () async {
                navigator.pop();
                say(await FolderContextActions.bookmark(services, folder));
                // Перерисовать экран: закладка появляется в боковой панели.
                await explorer.refresh();
              }),
              item('details', Icons.info_outline, _accent, 'Детали', () async {
                navigator.pop();
                if (!screen.mounted) return;
                await FolderDetailsSheet.show(screen, folder.path, services.folders);
              }),
              const SheetMenuSection('Буфер обмена'),
              item('copy', Icons.content_copy, _clipboard, 'Копировать', () async {
                navigator.pop();
                say(FolderContextActions.copy(services, folder));
                await explorer.refresh();
              }),
              item('cut', Icons.content_cut, _clipboard, 'Вырезать', () async {
                navigator.pop();
                say(FolderContextActions.cut(services, folder));
                await explorer.refresh();
              }),
              const SheetMenuSection('Изменить'),
              item('rename', Icons.drive_file_rename_outline, _edit, 'Переименовать', () async {
                navigator.pop();
                if (!services.folders.isEditable(folder.path)) return say(FolderContextActions.unavailable);
                if (!screen.mounted) return;
                final name = await RenameFolderDialog.show(screen, folder.name);
                if (name == null) return;
                say(await FolderContextActions.rename(services, folder, name));
                await changed();
              }),
              item('delete', Icons.delete_outline, _edit, 'Удалить', () async {
                navigator.pop();
                if (!services.folders.isEditable(folder.path)) return say(FolderContextActions.unavailable);
                if (!screen.mounted) return;
                final ok = await showConfirmDialog(
                  screen,
                  title: 'Удалить папку?',
                  message:
                      'Папка "${folder.name}" и всё её содержимое будут удалены без возможности восстановления.'
                      '${services.bookmarkController.hasUnder(folder.path) ? '\n\nВ закладках есть ссылки на удаляемые папки — они тоже будут удалены.' : ''}',
                  confirmLabel: 'Удалить',
                  cancelLabel: 'Отмена',
                );
                if (!ok) return;
                say(await FolderContextActions.delete(services, folder));
                await changed();
              }),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('folder_menu_cancel'),
                    onPressed: () => navigator.pop(),
                    style: TextButton.styleFrom(foregroundColor: _accent),
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
}

/// Сведения о папке: путь, подпапки, файлы, размер, последнее изменение.
class FolderDetailsSheet extends StatelessWidget {
  const FolderDetailsSheet({super.key, required this.details});

  final FolderDetails details;

  static Future<void> show(BuildContext context, String path, FolderService folders) async {
    final details = await folders.details(path);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => FolderDetailsSheet(details: details),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(details.lastModifiedMs);
    String two(int v) => v.toString().padLeft(2, '0');
    final rows = [
      ('Путь', details.path),
      ('Папок', '${details.folderCount}'),
      ('Файлов', '${details.fileCount}'),
      ('Размер', formatBytes(details.totalBytes)),
      ('Изменена', '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}'),
    ];
    return SafeArea(
      child: Padding(
        key: const Key('folder_details_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Детали', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
            ),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(k, style: const TextStyle(color: Color(0xFF757575))),
                    ),
                    Expanded(child: SelectableText(v)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
