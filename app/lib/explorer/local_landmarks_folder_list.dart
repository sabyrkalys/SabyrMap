import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:flutter/material.dart';

import 'explorer_style.dart';
import 'folder_row.dart';

/// Папки текущей папки.
class LocalLandmarksFolderList extends StatelessWidget {
  const LocalLandmarksFolderList({super.key, required this.folders, required this.onOpen});

  final List<ExplorerFolderNode> folders;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, f) in folders.indexed) ...[
        if (i > 0) const Padding(padding: EdgeInsets.only(left: 56), child: ExplorerStyle.divider1),
        FolderRow(path: f.path, name: f.name, onTap: () => onOpen(f.path)),
      ],
    ],
  );
}
