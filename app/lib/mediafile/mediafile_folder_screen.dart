import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'mediafile_folder_service.dart';
import '../format_bytes.dart';
import '../widgets/app_icon.dart';
import '../app_icons.dart';

typedef _Contents = ({List<String> folders, List<MediaFileEntry> files});

class MediaFileFolderScreen extends StatefulWidget {
  const MediaFileFolderScreen({
    super.key,
    required this.title,
    required this.subfolder,
    required this.allowedExtensions,
    this.service,
  });

  final String title;
  final String subfolder;
  /// Empty — any file.
  final List<String> allowedExtensions;
  final MediaFileFolderService? service;

  @override
  State<MediaFileFolderScreen> createState() => _MediaFileFolderScreenState();
}

class _MediaFileFolderScreenState extends State<MediaFileFolderScreen> {
  late final MediaFileFolderService _service =
      widget.service ?? MediaFileFolderService(subfolder: widget.subfolder);
  late Future<_Contents> _future = _load();

  /// Subfolders first (each opens as its own list), then the files.
  Future<_Contents> _load() async =>
      (folders: [for (final dir in await _service.listDirectories()) dir.basename], files: await _service.list());

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _openFolder(String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaFileFolderScreen(
          title: name,
          subfolder: widget.subfolder.isEmpty ? name : '${widget.subfolder}/$name',
          allowedExtensions: widget.allowedExtensions,
          service: _service.child(name),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _import() async {
    // FileType.any + own check: Android greys out files whose MIME type it
    // doesn't know (.mbtiles) under a custom filter.
    final result = await FilePicker.pickFiles(type: FileType.any);
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    final extension = path.split('.').last.toLowerCase();
    if (widget.allowedExtensions.isNotEmpty && !widget.allowedExtensions.contains(extension)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Подходят файлы: ${widget.allowedExtensions.join(', ')}')),
        );
      }
      return;
    }
    try {
      await _service.importFile(path);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось импортировать файл')),
        );
      }
    }
  }

  Future<void> _delete(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить файл «$fileName»?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.delete(fileName);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить файл')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('mediafile_import_button'),
            icon: const AppIcon(AppIcons.upload),
            onPressed: _import,
          ),
        ],
      ),
      body: FutureBuilder<_Contents>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Не удалось открыть папку'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (:folders, files: entries) = snapshot.data!;
          if (folders.isEmpty && entries.isEmpty) {
            return const Center(child: Text('Здесь пока нет файлов'));
          }
          return ListView.builder(
            itemCount: folders.length + entries.length,
            itemBuilder: (context, index) {
              if (index < folders.length) {
                final name = folders[index];
                return ListTile(
                  key: Key('mediafile_subfolder_$name'),
                  leading: const AppIcon(AppIcons.folder),
                  title: Text(name),
                  onTap: () => _openFolder(name),
                );
              }
              final entry = entries[index - folders.length];
              return ListTile(
                key: Key('mediafile_entry_${entry.fileName}'),
                title: Text(entry.fileName),
                subtitle: Text(formatBytes(entry.sizeBytes)),
                trailing: IconButton(
                  key: Key('mediafile_delete_${entry.fileName}'),
                  icon: const AppIcon(AppIcons.trash),
                  onPressed: () => _delete(entry.fileName),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
