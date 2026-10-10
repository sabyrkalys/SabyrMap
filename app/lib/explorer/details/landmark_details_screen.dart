import 'package:app/landmarks/composite/statistics/composite_statistics.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:path/path.dart' as p;

import '../../app/landmark_services_provider.dart';
import '../../map/map_focus.dart';
import '../descriptors/descriptor_registry.dart';
import '../descriptors/detail_data.dart';
import '../item_menu/item_context_menu.dart';
import '../item_menu/item_hooks.dart';
import 'landmark_details_actions_bar.dart';
import 'landmark_details_app_bar.dart';
import 'landmark_details_body.dart';
import 'landmark_geometry.dart';

/// Детализация метки любого типа: секции строятся из дескриптора типа.
class LandmarkDetailsScreen extends ConsumerStatefulWidget {
  const LandmarkDetailsScreen({super.key, required this.path});

  /// Абсолютный путь к файлу метки.
  final String path;

  /// Открывает детализацию. true — пользователь нажал ☰: проводнику
  /// открыть боковую панель.
  static Future<bool> open(BuildContext context, String path) async =>
      await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => LandmarkDetailsScreen(path: path))) ??
      false;

  @override
  ConsumerState<LandmarkDetailsScreen> createState() => _LandmarkDetailsScreenState();
}

class _LandmarkDetailsScreenState extends ConsumerState<LandmarkDetailsScreen> {
  late final LandmarkServices _services = ref.read(landmarkServicesProvider);
  late final LandmarkItemReader _reader = LandmarkItemReader(_services.storage);
  late String _path = widget.path;
  LandmarkDetailsData? _data;
  bool _missing = false;

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
    LandmarkObject? object;
    CompositeStatistics? stats;
    int? size;
    DateTime? modified;
    if (item != null) {
      try {
        object = (await _services.repository.load(path)).content;
        stats = _services.calculator.forObject(object);
      } on Exception {
        object = null;
      }
      try {
        size = await _services.folders.fileSize(path);
        modified = DateTime.fromMillisecondsSinceEpoch(await _services.folders.fileModifiedMs(path));
      } on Exception {
        size = null;
      }
    }
    if (!mounted || path != _path) return;
    setState(() {
      _missing = item == null;
      _data = item == null
          ? null
          : LandmarkDetailsData(
              item: item,
              object: object,
              stats: stats,
              folder: ref.read(markerGroupFoldersProvider).display(p.dirname(path)),
              sizeBytes: size,
              modified: modified,
            );
    });
  }

  void _renamed(String path) {
    _path = path;
    _reload();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Камера карты — на середину объекта; экран карты становится видимым.
  void _center() {
    final center = LandmarkGeometry.centerOf(_data?.object);
    if (center == null) return _snack('У объекта нет координат');
    ref.read(mapFocusProvider.notifier).focus(LatLng(center.latitude, center.longitude));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final name = data?.item.name ?? p.basenameWithoutExtension(_path);
    final descriptor = data == null ? null : ref.read(descriptorRegistryProvider).of(data.item.type);
    final shown = _services.displayRegistry.isDisplayed(_path);
    return ItemHooks(
      inDetails: true,
      onOpen: (_) async {},
      onRenamed: _renamed,
      onDeleted: () {
        if (mounted) Navigator.of(context).pop(false);
      },
      child: Builder(
        builder: (context) {
          // Меню открывается от контекста под хуками: действия находят их.
          void menu() {
            if (data != null) ItemContextMenu.show(context, data.item, compact: true);
          }

          return Scaffold(
            key: const Key('landmark_details_screen'),
            backgroundColor: Colors.white,
            floatingActionButton: FloatingActionButton(
              key: const Key('details_fab'),
              onPressed: () => _snack('Добавление объектов пока недоступно'),
              child: const Icon(Icons.add),
            ),
            body: Column(
              children: [
                LandmarkDetailsAppBar(
                  displayName: name,
                  onMenu: () => Navigator.pop(context, true),
                  onClose: () => Navigator.pop(context, false),
                  onMore: menu,
                ),
                LandmarkDetailsActionsBar(
                  displayed: shown,
                  onMore: menu,
                  onToggleDisplay: () => _services.displayRegistry.toggle(_path),
                  onCenter: descriptor?.hasLocation ?? false ? _center : null,
                ),
                Expanded(
                  child: data == null || descriptor == null
                      ? Center(
                          child: _missing
                              ? const Text('Файл не найден')
                              : const CircularProgressIndicator(key: Key('details_loading')),
                        )
                      : LandmarkDetailsBody(descriptor: descriptor, data: data, onMore: menu),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
