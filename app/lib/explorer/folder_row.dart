import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => ListTile(
    key: Key('folder_row_${widget.name}'),
    leading: const Icon(Icons.folder_outlined),
    title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: FutureBuilder<FolderCounts>(future: _counts, builder: (context, snap) => Text(snap.data?.label ?? ' ')),
    trailing: const Icon(Icons.chevron_right),
    onTap: widget.onTap,
  );
}
