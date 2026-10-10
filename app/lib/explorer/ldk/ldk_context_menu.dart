import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/landmark_services_provider.dart';
import '../../dialogs/confirm_dialog.dart';
import '../sheet_menu.dart';
import 'ldk_context_actions.dart';
import 'ldk_details_screen.dart';
import 'ldk_export_flow.dart';
import 'ldk_properties_dialog.dart';
import 'ldk_rename_dialog.dart';

/// Меню файла меток.
///
/// [show] (из списка): «Открыть», «Показать»/«Скрыть», «Поделиться»,
/// «Экспортировать как...»; БУФЕР ОБМЕНА — «Копировать», «Вырезать»;
/// МУЛЬТИВЫБОР — «Выбрать»; ИЗМЕНИТЬ — «Переименовать», «Изменить
/// свойства», «Удалить».
///
/// [showCompact] (из детализации): «Поделиться» и «Переименовать».
class LdkContextMenu extends StatelessWidget {
  const LdkContextMenu({
    super.key,
    required this.services,
    required this.path,
    required this.file,
    required this.compact,
    this.onRenamed,
    this.onDeleted,
    this.onOpen,
  });

  final LandmarkServices services;
  final String path;

  /// Содержимое файла; null — файл не прочитан (меню всё равно открыто).
  final LandmarkFile? file;
  final bool compact;

  /// Файл переименован — новый путь.
  final ValueChanged<String>? onRenamed;
  final VoidCallback? onDeleted;

  /// «Открыть»; null — [LdkDetailsScreen.open] поверх экрана.
  final Future<void> Function(String path)? onOpen;

  static Future<void> show(
    BuildContext context,
    String path, {
    ValueChanged<String>? onRenamed,
    VoidCallback? onDeleted,
    Future<void> Function(String path)? onOpen,
  }) => _open(
    context,
    path,
    compact: false,
    onRenamed: onRenamed,
    onDeleted: onDeleted,
    onOpen: onOpen,
  );

  static Future<void> showCompact(
    BuildContext context,
    String path, {
    ValueChanged<String>? onRenamed,
  }) => _open(context, path, compact: true, onRenamed: onRenamed);

  static Future<void> _open(
    BuildContext context,
    String path, {
    required bool compact,
    ValueChanged<String>? onRenamed,
    VoidCallback? onDeleted,
    Future<void> Function(String path)? onOpen,
  }) async {
    final services = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(landmarkServicesProvider);
    LandmarkFile? file;
    try {
      file = await services.repository.load(path);
    } on Exception {
      file = null;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LdkContextMenu(
        services: services,
        path: path,
        file: file,
        compact: compact,
        onRenamed: onRenamed,
        onDeleted: onDeleted,
        onOpen: onOpen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final explorer = services.explorerController;
    // Сообщения и диалоги — от экрана под шторкой: сама шторка закрывается.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final screen = navigator.context;
    final name = LdkContextActions.displayName(file, path);
    final shown = services.displayRegistry.isDisplayed(path);

    void say(String? text) {
      if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
    }

    Widget item(
      String key,
      IconData icon,
      Color color,
      String label,
      Future<void> Function() action,
    ) => SheetMenuItem(
      key: Key('ldk_menu_$key'),
      icon: icon,
      color: color,
      label: label,
      onTap: action,
    );

    final share = item(
      'share',
      Icons.share_outlined,
      SheetMenuColors.accent,
      'Поделиться',
      () async {
        navigator.pop();
        say(await LdkContextActions.share(services, path));
      },
    );
    final rename = item(
      'rename',
      Icons.drive_file_rename_outline,
      SheetMenuColors.edit,
      'Переименовать',
      () async {
        navigator.pop();
        if (!screen.mounted) return;
        final newName = await LdkRenameDialog.show(screen, name);
        if (newName == null) return;
        final result = await LdkContextActions.rename(services, path, newName);
        if (result == null) return;
        say(result.message);
        await explorer.refresh();
        if (result.path case final renamed?) onRenamed?.call(renamed);
      },
    );
    final cancel = SheetMenuCancel(
      buttonKey: const Key('ldk_menu_cancel'),
      onPressed: () => navigator.pop(),
    );

    return SheetMenu(
      key: Key(compact ? 'ldk_context_menu_compact' : 'ldk_context_menu'),
      title: name,
      children: compact
          ? [share, const SheetMenuSection('Изменить'), rename, cancel]
          : [
              item(
                'open',
                Icons.subdirectory_arrow_right,
                SheetMenuColors.accent,
                'Открыть',
                () async {
                  navigator.pop();
                  if (onOpen case final open?) return open(path);
                  if (screen.mounted) await LdkDetailsScreen.open(screen, path);
                },
              ),
              item(
                'display',
                Icons.visibility_outlined,
                SheetMenuColors.accent,
                shown ? 'Скрыть' : 'Показать',
                () async {
                  navigator.pop();
                  say(
                    LdkContextActions.toggleDisplay(services, path)
                        ? 'Показано на карте'
                        : 'Скрыто с карты',
                  );
                },
              ),
              share,
              item(
                'export',
                Icons.file_download_outlined,
                SheetMenuColors.accent,
                'Экспортировать как...',
                () async {
                  navigator.pop();
                  if (screen.mounted) await LdkExportFlow.start(screen, path);
                },
              ),
              const SheetMenuSection('Буфер обмена'),
              item(
                'copy',
                Icons.copy_outlined,
                SheetMenuColors.clipboard,
                'Копировать',
                () async {
                  navigator.pop();
                  say(LdkContextActions.copy(services, path, name));
                  await explorer.refresh();
                },
              ),
              item(
                'cut',
                Icons.content_cut,
                SheetMenuColors.clipboard,
                'Вырезать',
                () async {
                  navigator.pop();
                  say(LdkContextActions.cut(services, path, name));
                  await explorer.refresh();
                },
              ),
              const SheetMenuSection('Мультивыбор'),
              item(
                'select',
                Icons.check_box_outlined,
                SheetMenuColors.text,
                'Выбрать',
                () async {
                  navigator.pop();
                  LdkContextActions.select(services, path);
                },
              ),
              const SheetMenuSection('Изменить'),
              rename,
              item(
                'properties',
                Icons.edit_outlined,
                SheetMenuColors.edit,
                'Изменить свойства',
                () async {
                  navigator.pop();
                  if (!screen.mounted) return;
                  final current = file;
                  final props = await LdkPropertiesDialog.show(
                    screen,
                    initial: current == null
                        ? LdkProperties(name: name)
                        : LdkContextActions.propertiesOf(current, path),
                  );
                  if (props == null) return;
                  say(
                    await LdkContextActions.updateProperties(
                      services,
                      path,
                      props,
                    ),
                  );
                  await explorer.refresh();
                },
              ),
              item(
                'delete',
                Icons.delete_outline,
                SheetMenuColors.edit,
                'Удалить',
                () async {
                  navigator.pop();
                  if (!screen.mounted) return;
                  final ok = await showConfirmDialog(
                    screen,
                    title: 'Удалить файл?',
                    message:
                        'Файл "$name" будет удалён без возможности восстановления.',
                    confirmLabel: 'Удалить',
                    cancelLabel: 'Отмена',
                  );
                  if (!ok) return;
                  say(await LdkContextActions.delete(services, path));
                  await explorer.refresh();
                  onDeleted?.call();
                },
              ),
              cancel,
            ],
    );
  }
}
