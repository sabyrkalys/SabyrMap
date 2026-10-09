import 'package:flutter/material.dart';

import 'explorer_style.dart';
import 'folder_count_badge.dart';

/// Строка папки: иконка, имя, «X папок · Y файл.».
class FolderRow extends StatefulWidget {
  const FolderRow({super.key, required this.path, required this.name, required this.onTap});

  final String path;
  final String name;
  final VoidCallback onTap;

  @override
  State<FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<FolderRow> {
  late Future<FolderCounts> _counts = FolderCounts.of(widget.path);

  @override
  void didUpdateWidget(FolderRow old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _counts = FolderCounts.of(widget.path);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('folder_row_${widget.name}'),
    onTap: widget.onTap,
    child: SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.folder_outlined, size: 24, color: ExplorerStyle.icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name, style: ExplorerStyle.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                FutureBuilder<FolderCounts>(
                  future: _counts,
                  builder: (context, snap) => Text(snap.data?.label ?? ' ', style: ExplorerStyle.subtitle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );
}
