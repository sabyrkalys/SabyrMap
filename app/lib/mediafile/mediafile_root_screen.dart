import 'package:flutter/material.dart';

import 'mediafile_folder_screen.dart';
import 'mediafile_folder_service.dart';
import 'mediafile_subfolders.dart';

/// What a known subfolder is called and which files it takes.
class MediaFileSubfolder {
  const MediaFileSubfolder(this.title, this.allowedExtensions);

  final String title;

  /// Empty — any file.
  final List<String> allowedExtensions;
}

const kMediaFileSubfolders = {
  kMapsSubfolder: MediaFileSubfolder('Карты', ['mbtiles']),
  kOrthophotoSubfolder: MediaFileSubfolder('Ортофото', ['mbtiles']),
  kCustomTypesSubfolder: MediaFileSubfolder('Файлы меток', ['png', 'jpg', 'jpeg', 'svg']),
};

/// The mediafile folder itself: its subfolders, each opening as a file list.
class MediaFileRootScreen extends StatefulWidget {
  const MediaFileRootScreen({super.key, this.service, this.onChanged});

  final MediaFileFolderService? service;

  /// After a subfolder screen is closed (files may have been added or deleted).
  final VoidCallback? onChanged;

  @override
  State<MediaFileRootScreen> createState() => _MediaFileRootScreenState();
}

class _MediaFileRootScreenState extends State<MediaFileRootScreen> {
  late final MediaFileFolderService _service = widget.service ?? MediaFileFolderService(subfolder: '');
  late final Future<List<String>> _future = _subfolders();

  /// Known subfolders always (they are created on demand), then whatever else is there.
  Future<List<String>> _subfolders() async {
    final present = [for (final dir in await _service.listDirectories()) dir.basename];
    return [...kMediaFileSubfolders.keys, ...present.where((name) => !kMediaFileSubfolders.containsKey(name))];
  }

  Future<void> _open(String name) async {
    final known = kMediaFileSubfolders[name];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaFileFolderScreen(
          title: known?.title ?? name,
          subfolder: name,
          allowedExtensions: known?.allowedExtensions ?? const [],
        ),
      ),
    );
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Медиафайлы')),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Не удалось открыть папку'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: [
              for (final name in snapshot.data!)
                ListTile(
                  key: Key('mediafile_folder_$name'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(kMediaFileSubfolders[name]?.title ?? name),
                  subtitle: Text('mediafile/$name/'),
                  onTap: () => _open(name),
                ),
            ],
          );
        },
      ),
    );
  }
}
