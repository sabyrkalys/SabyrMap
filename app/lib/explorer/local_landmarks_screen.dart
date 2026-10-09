import 'package:app/derived_export/details_renderer.dart';
import 'package:app/landmarks/explorer/explorer_controller.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/explorer_view_mode.dart';
import 'package:app/landmarks/explorer/listing/filter_options.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:app/landmarks/explorer/statistics/statistics_calculator.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/landmark_services_provider.dart';
import '../dialogs/confirm_dialog.dart';
import '../map/screens/available_maps/available_maps_models.dart';
import '../waypoints/waypoint_actions.dart';
import '../waypoints/waypoint_create_action.dart';
import '../waypoints/waypoints_controller.dart';
import 'explorer_breadcrumbs.dart';
import 'explorer_fab_menu.dart';
import 'explorer_providers.dart';
import 'explorer_style.dart';
import 'explorer_view_mode_switch.dart';
import 'local_landmarks_app_bar.dart';
import 'local_landmarks_drawer.dart';
import 'local_landmarks_folder_list.dart';
import 'local_landmarks_item_list.dart';
import 'permission_banner.dart';

/// «Локальные метки»: папки и файлы меток на устройстве, разделы в боковом
/// меню, создание, импорт, выбор и удаление.
class LocalLandmarksScreen extends ConsumerStatefulWidget {
  const LocalLandmarksScreen({super.key, this.initialFolder});

  /// Папка, открытая при входе; null — корень «Мои метки».
  final String? initialFolder;

  @override
  ConsumerState<LocalLandmarksScreen> createState() => _LocalLandmarksScreenState();
}

class _LocalLandmarksScreenState extends ConsumerState<LocalLandmarksScreen> {
  late final LandmarkServices _services = ref.read(landmarkServicesProvider);
  ExplorerController get _explorer => _services.explorerController;

  List<PlaceRoot> _places = const [];
  StorageUsage? _deviceUsage;
  String? _shownError;
  String? _accessFolder;
  bool _hasAccess = true;

  @override
  void initState() {
    super.initState();
    _explorer.addListener(_onExplorer);
    _explorer.selection.addListener(_onExplorer);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
  }

  @override
  void dispose() {
    _explorer.removeListener(_onExplorer);
    _explorer.selection.removeListener(_onExplorer);
    _explorer.selection.deactivate();
    super.dispose();
  }

  /// «Назад» снимает выбор или поднимается на папку выше; в корне места
  /// закрывает экран.
  bool get _canPop {
    final state = _explorer.state;
    final folder = state.currentFolder;
    final root = state.currentPlace?.path;
    if (_explorer.selection.state.isActive) return false;
    return folder == null || root == null || !p.isWithin(root, folder);
  }

  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_explorer.selection.state.isActive) {
      _explorer.selection.deactivate();
    } else {
      _explorer.goUp();
    }
  }

  Future<void> _openInitial() async {
    _places = await _services.placesProvider.listPlaces();
    final device = _places.where((pl) => pl.kind == PlaceRootKind.deviceFolder).firstOrNull;
    if (device != null) _deviceUsage = await _usageOf(device.path);
    if (!mounted) return;
    final landmarks = _places.where((pl) => pl.kind == PlaceRootKind.landmarks).firstOrNull;
    final initial = widget.initialFolder;
    if (landmarks != null) {
      await _explorer.openPlace(landmarks);
      if (initial != null && !p.equals(initial, landmarks.path)) await _explorer.openFolder(initial);
    } else if (initial != null) {
      await _explorer.openFolder(initial);
    }
  }

  Future<StorageUsage?> _usageOf(String path) async {
    final info = ref.read(storageInfoProvider);
    final total = await info.totalBytes(path);
    final free = await info.freeBytes(path);
    if (total == null || free == null || total <= 0) return null;
    return StorageUsage(path: path, usedBytes: total - free, totalBytes: total);
  }

  void _onExplorer() {
    if (!mounted) return;
    final state = _explorer.state;
    final error = state.errorMessage;
    if (error != null && error != _shownError) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
    _shownError = error;
    final folder = state.currentFolder;
    if (folder != null && folder != _accessFolder && !state.isLoading) {
      _accessFolder = folder;
      _services.permissionService.hasAccess(folder).then((ok) {
        if (mounted && _accessFolder == folder) setState(() => _hasAccess = ok);
      });
    }
    setState(() {});
  }

  /// Файлы на диске изменились — обновить список и точки на карте.
  Future<void> _changed() async {
    await _explorer.refresh();
    await ref.read(waypointsControllerProvider.notifier).loadWaypoints();
  }

  Future<void> _activate() async {
    final granted = await _services.permissionService.request();
    if (!mounted) return;
    if (granted) {
      await _explorer.refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Доступ не предоставлен')));
    }
  }

  Future<void> _onPlace(PlaceRoot place) async {
    Navigator.of(context).pop();
    await _explorer.openPlace(place);
  }

  Future<void> _onItemTap(LandmarkItem item) async {
    final selection = _explorer.selection;
    if (selection.state.isActive) {
      selection.toggle(item.path);
      return;
    }
    if (item.type == LandmarkType.waypoint) {
      final waypoint = ref.read(waypointsControllerProvider).where((w) => w.id == item.path).firstOrNull;
      if (waypoint != null) {
        await showWaypointDetails(context, ref, waypoint);
        await _explorer.refresh();
        return;
      }
    }
    await _showDetails(item);
  }

  void _onItemLongPress(LandmarkItem item) {
    final selection = _explorer.selection;
    if (!selection.state.isActive) selection.activate();
    selection.toggle(item.path);
  }

  Future<void> _showDetails(LandmarkItem item) async {
    String text;
    try {
      final object = (await _services.repository.load(item.path)).content;
      text = DetailsRenderer.render(
        object,
        _services.calculator.forObject(object),
        locale: _services.appSettingsController.model.locale,
      );
    } on Exception catch (e) {
      text = 'Не удалось прочитать файл: $e';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ЗАКРЫТЬ'))],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final paths = _explorer.selection.snapshot();
    if (paths.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить ${paths.length} файл.?',
      message: 'Файлы будут удалены с устройства без возможности восстановления.',
      confirmLabel: 'УДАЛИТЬ',
    );
    if (!ok) return;
    final result = await _services.explorerOperations.deleteSelected(paths);
    _explorer.selection.deactivate();
    await _changed();
    if (!mounted || result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.errorMessage ?? 'Не всё удалено')));
  }

  Future<void> _onFab(ExplorerFabAction action) async {
    final folder = _explorer.state.currentFolder;
    switch (action) {
      case ExplorerFabAction.newFolder:
        if (folder == null) return;
        final name = await _askFolderName();
        if (name == null) return;
        try {
          await _services.folders.ensureFolder(p.join(folder, name));
          await _explorer.refresh();
        } on Exception catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось создать: $e')));
        }
      case ExplorerFabAction.newMarker:
        await createWaypointAtCrosshair(context, ref);
        await _changed();
      case ExplorerFabAction.importFile:
        final picked = await FilePicker.pickFiles();
        final path = picked?.files.firstOrNull?.path;
        if (path == null) return;
        final result = await _services.importService.importFromFile(path, targetFolder: folder);
        await _changed();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success ? 'Импортировано: ${result.importedCount}' : (result.errorMessage ?? 'Импорт не удался'),
            ),
          ),
        );
    }
  }

  Future<String?> _askFolderName() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NewFolderDialog());
    final trimmed = name?.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _onMenu(ExplorerMenuAction action) async {
    switch (action) {
      case ExplorerMenuAction.sort:
        final sort = await _pickSort(_explorer.state.sort);
        if (sort != null) await _explorer.setSort(sort);
      case ExplorerMenuAction.filter:
        final filter = await _pickFilter(_explorer.state.filter);
        if (filter != null) await _explorer.setFilter(filter);
      case ExplorerMenuAction.statistics:
        await _showStatistics();
      case ExplorerMenuAction.selectAll:
        _explorer.selection
          ..activate()
          ..selectAll([for (final n in _explorer.state.nodes.whereType<ExplorerItemNode>()) n.path]);
      case ExplorerMenuAction.viewMode:
        await _explorer.setViewMode(ExplorerViewModeSwitch.next(_explorer.state.viewMode));
    }
  }

  Future<SortOptions?> _pickSort(SortOptions current) => showModalBottomSheet<SortOptions>(
    context: context,
    backgroundColor: ExplorerStyle.drawerBackground,
    builder: (context) {
      const labels = {
        SortField.name: 'По имени',
        SortField.date: 'По дате',
        SortField.distanceFromScreenCenter: 'По расстоянию от центра',
        SortField.length: 'По длине',
        SortField.duration: 'По длительности',
        SortField.elevationGain: 'По набору высоты',
        SortField.area: 'По площади',
      };
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final field in SortField.values)
              ListTile(
                key: Key('sort_${field.name}'),
                title: Text(labels[field]!),
                trailing: field == current.field
                    ? Icon(
                        current.direction == SortDirection.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        color: ExplorerStyle.accent,
                      )
                    : null,
                onTap: () => Navigator.pop(
                  context,
                  field == current.field
                      ? current.copyWith(
                          direction: current.direction == SortDirection.ascending
                              ? SortDirection.descending
                              : SortDirection.ascending,
                        )
                      : SortOptions(field: field),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<ItemFilter?> _pickFilter(ItemFilter current) => showModalBottomSheet<ItemFilter>(
    context: context,
    backgroundColor: ExplorerStyle.drawerBackground,
    builder: (context) {
      const labels = {
        null: 'Все типы',
        LandmarkType.waypoint: 'Путевые точки',
        LandmarkType.set: 'Наборы точек',
        LandmarkType.route: 'Маршруты',
        LandmarkType.track: 'Треки',
        LandmarkType.area: 'Области',
      };
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final MapEntry(key: type, value: label) in labels.entries)
              ListTile(
                key: Key('filter_${type?.extension ?? 'all'}'),
                title: Text(label),
                trailing: current.onlyType == type ? const Icon(Icons.check, color: ExplorerStyle.accent) : null,
                onTap: () => Navigator.pop(context, current.copyWith(onlyType: type)),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _showStatistics() {
    final stats = const StatisticsCalculator().calculate(_explorer.allItems);
    String km(double m) => '${(m / 1000).toStringAsFixed(2)} км';
    final d = Duration(milliseconds: stats.totalDurationMs);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Статистика'),
        content: Column(
          key: const Key('explorer_statistics'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Файлов: ${stats.itemCount}'),
            Text('Длина: ${km(stats.totalLengthMeters)}'),
            Text('Время в пути: ${d.inHours} ч ${d.inMinutes % 60} мин'),
            Text('Набор высоты: ${stats.totalElevationGainMeters.round()} м'),
            Text('Площадь: ${(stats.totalAreaSquareMeters / 1e6).toStringAsFixed(3)} км²'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ЗАКРЫТЬ'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _explorer.state;
    final selection = _explorer.selection.state;
    final folders = state.nodes.whereType<ExplorerFolderNode>().toList();
    final items = state.nodes.whereType<ExplorerItemNode>().toList();
    final place = state.currentPlace;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        backgroundColor: ExplorerStyle.background,
        appBar: LocalLandmarksAppBar(
          subtitle: ExplorerBreadcrumbs.of(
            place == null
                ? null
                : PlaceRoot(
                    id: place.id,
                    title: LocalLandmarksDrawer.titleOf(place, _deviceUsage),
                    path: place.path,
                    kind: place.kind,
                  ),
            state.currentFolder,
          ),
          viewMode: state.viewMode,
          onMenuAction: _onMenu,
        ),
        drawer: LocalLandmarksDrawer(
          places: _places,
          currentPlace: place,
          deviceUsage: _deviceUsage,
          onPlace: _onPlace,
        ),
        floatingActionButton: selection.isActive ? null : ExplorerFabMenu(onAction: _onFab),
        bottomNavigationBar: selection.isActive
            ? SafeArea(
                child: Container(
                  key: const Key('explorer_selection_bar'),
                  height: 56,
                  decoration: const BoxDecoration(
                    color: ExplorerStyle.drawerBackground,
                    border: Border(top: BorderSide(color: ExplorerStyle.divider)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(child: Text('Выбрано: ${selection.count}', style: ExplorerStyle.rowTitle)),
                      IconButton(
                        key: const Key('selection_delete'),
                        tooltip: 'Удалить',
                        icon: const Icon(Icons.delete_outline, color: ExplorerStyle.icon),
                        onPressed: selection.count == 0 ? null : _deleteSelected,
                      ),
                      TextButton(
                        key: const Key('selection_cancel'),
                        onPressed: _explorer.selection.deactivate,
                        child: const Text('ОТМЕНА'),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            if (!_hasAccess) PermissionBanner(onActivate: _activate),
            Expanded(
              child: state.isLoading || state.currentFolder == null
                  ? const Center(child: CircularProgressIndicator(key: Key('explorer_loading')))
                  : state.nodes.isEmpty
                  ? const Center(
                      key: Key('explorer_empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: ExplorerStyle.emptyIcon),
                          SizedBox(height: 8),
                          Text('Папка пуста', style: TextStyle(fontSize: 14, color: ExplorerStyle.secondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _explorer.refresh,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          LocalLandmarksFolderList(folders: folders, onOpen: _explorer.openFolder),
                          if (folders.isNotEmpty && items.isNotEmpty) ExplorerStyle.divider1,
                          LocalLandmarksItemList(
                            items: items,
                            selecting: selection.isActive,
                            isSelected: selection.contains,
                            dense: state.viewMode == ExplorerViewMode.list,
                            onTap: _onItemTap,
                            onLongPress: _onItemLongPress,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Имя новой папки; поле живёт столько же, сколько диалог.
class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog();

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая папка'),
    content: TextField(
      key: const Key('new_folder_name'),
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'Название'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОТМЕНА')),
      TextButton(
        key: const Key('new_folder_ok'),
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('ОК'),
      ),
    ],
  );
}
