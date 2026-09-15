import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'mediafile_folder_service.dart';

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
  final List<String> allowedExtensions;
  final MediaFileFolderService? service;

  @override
  State<MediaFileFolderScreen> createState() => _MediaFileFolderScreenState();
}

class _MediaFileFolderScreenState extends State<MediaFileFolderScreen> {
  late final MediaFileFolderService _service =
      widget.service ?? MediaFileFolderService(subfolder: widget.subfolder);
  late Future<List<MediaFileEntry>> _future = _service.list();

  void _reload() {
    final next = _service.list();
    setState(() {
      _future = next;
    });
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions,
    );
    final path = result?.files.first.path;
    if (path == null) return;
    await _service.importFile(path);
    _reload();
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
    if (confirmed != true) return;
    await _service.delete(fileName);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('mediafile_import_button'),
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _import,
          ),
        ],
      ),
      body: FutureBuilder<List<MediaFileEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('Здесь пока нет файлов'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                key: Key('mediafile_entry_${entry.fileName}'),
                title: Text(entry.fileName),
                subtitle: Text('${(entry.sizeBytes / 1024).ceil()} КБ'),
                trailing: IconButton(
                  key: Key('mediafile_delete_${entry.fileName}'),
                  icon: const Icon(Icons.delete_outline),
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
