import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/landmark_services_provider.dart';
import '../sheet_menu.dart';
import 'ldk_context_menu.dart';
import 'ldk_details_app_bar.dart';
import 'ldk_details_file_section.dart';

/// Детализация файла меток: панель действий (⋮, «ЦЕНТРИРОВАТЬ», показ на
/// карте) и секция «ФАЙЛ».
class LdkDetailsScreen extends ConsumerStatefulWidget {
  const LdkDetailsScreen({super.key, required this.path});

  /// Абсолютный путь к `.ldk`.
  final String path;

  /// Открывает детализацию. true — пользователь нажал ☰: проводнику
  /// открыть боковую панель.
  static Future<bool> open(BuildContext context, String path) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => LdkDetailsScreen(path: path)),
      ) ??
      false;

  @override
  ConsumerState<LdkDetailsScreen> createState() => _LdkDetailsScreenState();
}

class _LdkDetailsScreenState extends ConsumerState<LdkDetailsScreen> {
  late final LandmarkServices _services = ref.read(landmarkServicesProvider);
  late final LandmarkItemReader _reader = LandmarkItemReader(_services.storage);
  late String _path = widget.path;
  LandmarkItem? _item;
  int? _size;
  DateTime? _modified;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _services.explorerController.addListener(_reload);
    _services.displayRegistry.addListener(_onDisplay);
    _reload();
  }

  @override
  void dispose() {
    _services.explorerController.removeListener(_reload);
    _services.displayRegistry.removeListener(_onDisplay);
    super.dispose();
  }

  void _onDisplay() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final path = _path;
    final item = await _reader.read(path);
    int? size;
    DateTime? modified;
    try {
      size = await _services.folders.fileSize(path);
      modified = DateTime.fromMillisecondsSinceEpoch(
        await _services.folders.fileModifiedMs(path),
      );
    } on Exception {
      size = null;
    }
    if (!mounted || path != _path) return;
    setState(() {
      _item = item;
      _size = size;
      _modified = modified;
    });
  }

  void _renamed(String path) {
    _path = path;
    _reload();
  }

  Future<void> _menu() =>
      LdkContextMenu.showCompact(context, _path, onRenamed: _renamed);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final name = _item?.name ?? p.basenameWithoutExtension(_path);
    final shown = _services.displayRegistry.isDisplayed(_path);
    return Scaffold(
      key: const Key('ldk_details_screen'),
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        key: const Key('ldk_details_fab'),
        onPressed: () => _snack('В файл пока нельзя добавлять объекты'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          LdkDetailsAppBar(
            displayName: name,
            onMenu: () => Navigator.pop(context, true),
            onClose: () => Navigator.pop(context, false),
            onMore: _menu,
          ),
          Container(
            key: const Key('ldk_details_actions'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const Key('ldk_details_more'),
                  icon: const Icon(Icons.more_vert),
                  onPressed: _menu,
                ),
                const Spacer(),
                TextButton(
                  key: const Key('ldk_details_center'),
                  onPressed: () =>
                      _snack('В файле нет объектов с координатами'),
                  style: TextButton.styleFrom(
                    foregroundColor: SheetMenuColors.text,
                  ),
                  child: const Text(
                    'ЦЕНТРИРОВАТЬ',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  key: const Key('ldk_details_visibility'),
                  tooltip: shown ? 'Скрыть с карты' : 'Показать на карте',
                  icon: Icon(
                    shown ? Icons.visibility : Icons.visibility_outlined,
                  ),
                  color: shown ? SheetMenuColors.accent : null,
                  onPressed: () => _services.displayRegistry.toggle(_path),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 88,
              ),
              child: LdkDetailsFileSection(
                name: name,
                folder: ref
                    .read(markerGroupFoldersProvider)
                    .display(p.dirname(_path)),
                sizeBytes: _size,
                modified: _modified,
                expanded: _expanded,
                onToggle: () => setState(() => _expanded = !_expanded),
                onMore: _menu,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
