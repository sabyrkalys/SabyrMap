import 'package:flutter/material.dart';

import 'explorer_style.dart';

/// Что можно создать из «+».
enum ExplorerFabAction { newFolder, newMarker, importFile }

/// Кнопка «+»: меню «Новая папка», «Новая метка», «Импорт файла».
class ExplorerFabMenu extends StatelessWidget {
  const ExplorerFabMenu({super.key, required this.onAction});

  final ValueChanged<ExplorerFabAction> onAction;

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    key: const Key('explorer_fab'),
    backgroundColor: Colors.white,
    foregroundColor: ExplorerStyle.accent,
    onPressed: () async {
      final action = await showModalBottomSheet<ExplorerFabAction>(
        context: context,
        backgroundColor: ExplorerStyle.drawerBackground,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (action, icon, label) in const [
                (ExplorerFabAction.newFolder, Icons.create_new_folder_outlined, 'Новая папка'),
                (ExplorerFabAction.newMarker, Icons.add_location_alt_outlined, 'Новая метка'),
                (ExplorerFabAction.importFile, Icons.file_download_outlined, 'Импорт файла'),
              ])
                ListTile(
                  key: Key('fab_${action.name}'),
                  leading: Icon(icon, color: ExplorerStyle.icon),
                  title: Text(label, style: ExplorerStyle.rowTitle),
                  onTap: () => Navigator.pop(context, action),
                ),
            ],
          ),
        ),
      );
      if (action != null) onAction(action);
    },
    child: const Icon(Icons.add),
  );
}
