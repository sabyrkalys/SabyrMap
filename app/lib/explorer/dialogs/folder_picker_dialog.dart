import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../sheet_menu.dart';

/// Выбор папки внутри [root]: переход по подпапкам, «..» — на уровень
/// выше, «Создать папку» — тут же. Результат — путь или null («ОТМЕНА»).
class FolderPickerDialog extends StatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.folders,
    required this.root,
    required this.rootTitle,
    this.initial,
  });

  final FolderService folders;

  /// Верх дерева: выше подняться нельзя.
  final String root;

  /// Как называть [root] в пути («Мои метки»).
  final String rootTitle;

  /// Открытая при входе папка; вне [root] — открывается [root].
  final String? initial;

  static Future<String?> show(
    BuildContext context, {
    required FolderService folders,
    required String root,
    String rootTitle = 'Мои метки',
    String? initial,
  }) => showDialog<String>(
    context: context,
    builder: (_) => FolderPickerDialog(folders: folders, root: root, rootTitle: rootTitle, initial: initial),
  );

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  late String _current = _inside(widget.initial) ? widget.initial! : widget.root;
  List<String>? _subfolders;
  bool _creating = false;
  String? _error;
  final TextEditingController _newName = TextEditingController();

  bool _inside(String? path) => path != null && (p.equals(widget.root, path) || p.isWithin(widget.root, path));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = _current;
    List<String> subfolders;
    try {
      subfolders = await widget.folders.listSubfolders(path);
    } on Exception {
      subfolders = const [];
    }
    if (mounted && path == _current) setState(() => _subfolders = subfolders);
  }

  void _open(String path) {
    setState(() {
      _current = path;
      _subfolders = null;
    });
    _load();
  }

  Future<void> _create() async {
    try {
      final created = await widget.folders.createSubfolder(_current, _newName.text);
      _newName.clear();
      setState(() {
        _creating = false;
        _error = null;
      });
      _open(created);
    } on FolderException catch (e) {
      setState(() => _error = e.message);
    } on StorageException catch (e) {
      setState(() => _error = e.message);
    }
  }

  String get _title => p.equals(widget.root, _current)
      ? widget.rootTitle
      : [widget.rootTitle, ...p.split(p.relative(_current, from: widget.root))].join(' / ');

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final subfolders = _subfolders;
    const button = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5);
    return AlertDialog(
      key: const Key('folder_picker_dialog'),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: width * 0.075, vertical: 24),
      title: Text(_title, key: const Key('folder_picker_path'), style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: width * 0.85,
        height: 320,
        child: Column(
          children: [
            Expanded(
              child: subfolders == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (!p.equals(widget.root, _current))
                          ListTile(
                            key: const Key('folder_picker_up'),
                            leading: const Icon(Icons.arrow_upward),
                            title: const Text('..'),
                            onTap: () => _open(p.dirname(_current)),
                          ),
                        for (final folder in subfolders)
                          ListTile(
                            key: Key('folder_picker_${p.basename(folder)}'),
                            leading: const Icon(Icons.folder_outlined, color: SheetMenuColors.accent),
                            title: Text(p.basename(folder)),
                            onTap: () => _open(folder),
                          ),
                      ],
                    ),
            ),
            if (_creating)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('folder_picker_new_name'),
                      controller: _newName,
                      autofocus: true,
                      decoration: InputDecoration(hintText: 'Имя папки', errorText: _error),
                      onSubmitted: (_) => _create(),
                    ),
                  ),
                  IconButton(key: const Key('folder_picker_new_ok'), icon: const Icon(Icons.check), onPressed: _create),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('folder_picker_create'),
                  onPressed: () => setState(() => _creating = true),
                  style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Создать папку'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('folder_picker_cancel'),
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
          child: const Text('ОТМЕНА', style: button),
        ),
        TextButton(
          key: const Key('folder_picker_choose'),
          onPressed: () => Navigator.pop(context, _current),
          style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
          child: const Text('ВЫБРАТЬ', style: button),
        ),
      ],
    );
  }
}
