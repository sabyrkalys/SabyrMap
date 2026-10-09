import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:flutter/material.dart';

import 'folder_row.dart';

/// Папки текущей папки.
class LocalLandmarksFolderList extends StatelessWidget {
  const LocalLandmarksFolderList({super.key, required this.folders, required this.onOpen, this.onMenu});

  final List<ExplorerFolderNode> folders;
  final ValueChanged<String> onOpen;

  /// Меню папки (долгое нажатие).
  final ValueChanged<ExplorerFolderNode>? onMenu;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final f in folders)
        FolderRow(
          path: f.path,
          name: f.name,
          onTap: () => onOpen(f.path),
          onLongPress: onMenu == null ? null : () => onMenu!(f),
        ),
    ],
  );
}
