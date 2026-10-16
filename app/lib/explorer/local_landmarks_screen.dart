import 'package:app/landmarks/explorer/explorer_controller.dart';
import 'package:app/landmarks/explorer/explorer_state.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/explorer_view_mode.dart';
import 'package:app/landmarks/explorer/listing/filter_options.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/explorer/statistics/statistics_calculator.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/landmark_services_provider.dart';
import '../dialogs/confirm_dialog.dart';
import '../map/map_crosshair.dart';
import '../map/screens/available_maps/available_maps_models.dart';
import '../map/screens/available_maps/maps_app_bar.dart';
import '../map/screens/available_maps/storage_bar.dart';
import '../waypoints/new_marker/marker_type.dart';
import '../waypoints/new_marker/new_marker_sheet.dart';
import '../waypoints/waypoint_create_action.dart';
import 'explorer_breadcrumbs.dart';
import 'explorer_create_sheet.dart';
import 'explorer_dropdown_menu.dart';
import 'explorer_providers.dart';
import 'explorer_view_mode_switch.dart';
import 'folder_context_actions.dart';
import 'folder_context_menu.dart';
import 'descriptors/descriptor_registry.dart';
import 'descriptors/landmark_type_descriptor.dart';
import 'details/landmark_details_screen.dart';
import 'item_menu/item_context_menu.dart';
import 'item_menu/item_hooks.dart';
import 'landmark_type_section.dart';
import 'section_menu/section_actions.dart';
import 'section_menu/section_context_menu.dart';
import 'ldk/ldk_create_dialog.dart';
import 'ldk/ldk_import_flow.dart';
import 'local_landmarks_drawer.dart';
import 'local_landmarks_folder_list.dart';
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

  /// Память раздела с текущей папкой.
  StorageUsage? _folderUsage;
  bool _drawerOpen = false;
  bool _menuOpen = false;
  String? _shownError;
  String? _accessFolder;
  bool _hasAccess = true;

  /// Контекст под [ItemHooks] — для меню элементов и секций.
  BuildContext? _hooksContext;

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
    if (_drawerOpen || _menuOpen || _explorer.selection.state.isActive) return false;
    return folder == null || root == null || !p.isWithin(root, folder);
  }

  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_drawerOpen || _menuOpen) {
      setState(() => _drawerOpen = _menuOpen = false);
    } else if (_explorer.selection.state.isActive) {
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
      _usageOf(folder).then((usage) {
        if (mounted && _accessFolder == folder) setState(() => _folderUsage = usage);
      });
    }
    setState(() {});
  }

  /// Файлы на диске изменились — обновить список (карта узнаёт об этом
  /// из индекса меток сама).
  Future<void> _changed() => _explorer.refresh();

  Future<void> _activate() async {
    final granted = await _services.permissionService.request();
    if (!mounted) return;
    if (granted) {
      await _explorer.refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Доступ не предоставлен')));
    }
  }

  /// Открывает папку закладки внутри её раздела (чтобы «Назад» и путь в
  /// шапке шли от раздела).
  Future<void> _openBookmark(String path) async {
    setState(() => _drawerOpen = false);
    final place = _places.where((pl) => p.equals(pl.path, path) || p.isWithin(pl.path, path)).firstOrNull;
    if (place != null && _explorer.state.currentPlace?.id != place.id) await _explorer.openPlace(place);
    await _explorer.openFolder(path);
  }

  Future<void> _onPlace(PlaceRoot place) async {
    setState(() => _drawerOpen = false);
    await _explorer.openPlace(place);
  }

  /// Короткое нажатие: в режиме выбора — отметка, иначе — детализация.
  Future<void> _onItemTap(LandmarkItem item) async {
    final selection = _explorer.selection;
    if (selection.state.isActive) {
      selection.toggle(item.path);
      return;
    }
    await _openDetails(item.path);
  }

  /// Долгое нажатие: в режиме выбора — отметка, иначе — меню элемента.
  Future<void> _onItemLongPress(LandmarkItem item) async {
    final selection = _explorer.selection;
    if (selection.state.isActive) return selection.toggle(item.path);
    await ItemContextMenu.show(_hooksContext ?? context, item);
  }

  /// Детализация метки; ☰ в ней открывает боковую панель здесь.
  Future<void> _openDetails(String path) async {
    final openDrawer = await LandmarkDetailsScreen.open(context, path);
    if (!mounted) return;
    if (openDrawer) setState(() => _drawerOpen = true);
    await _changed();
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

  Future<void> _create() async {
    final type = await showExplorerCreateSheet(context);
    if (type == null || !mounted) return;
    final folder = _explorer.state.currentFolder;
    if (folder == null) return;
    switch (type.id) {
      case ExplorerCreateIds.folder:
        final name = await _askName('Новая папка');
        if (name == null) return;
        await _guard(() => _services.folders.ensureFolder(p.join(folder, name)));
        await _explorer.refresh();
      case ExplorerCreateIds.landmarkFile:
        await _createLdk(folder);
      case ExplorerCreateIds.import:
        await _import(folder);
      case MarkerTypeIds.waypoint:
        await createWaypointAtCrosshair(context, ref, folder: folder);
        await _changed();
      case 'waypoint_set' || 'route' || 'path' || 'area':
        await _createComposite(type, folder);
      default:
        _snack('«${type.title}» пока нельзя создать: формат меток этого не поддерживает');
    }
  }

  /// Набор, маршрут, путь или область с первой точкой у прицела карты.
  Future<void> _createComposite(MarkerType type, String folder) async {
    final at = ref.read(mapCrosshairProvider);
    if (at == null) return _snack('Карта ещё не готова');
    final name = await _askName(type.title);
    if (name == null) return;
    final anchor = LandmarkLocation(latitude: at.latitude, longitude: at.longitude);
    final creation = _services.compositeCreation;
    await _guard(() async {
      switch (type.id) {
        case 'waypoint_set':
          await creation.createSet(SetDraft(name: name, targetFolder: folder), anchor);
        case 'route':
          await creation.createRoute(RouteDraft(name: name, targetFolder: folder), anchor);
        case 'path':
          await creation.createTrack(TrackDraft(name: name, targetFolder: folder, initialLocations: [anchor]), anchor);
        case 'area':
          await creation.createArea(AreaDraft(name: name, targetFolder: folder, isClosed: false), anchor);
      }
    });
    await _explorer.refresh();
  }

  Future<void> _import(String folder) async {
    final result = await LdkImportFlow.start(context, _services, folder);
    if (result != null) await _changed();
  }

  /// Новый файл меток (`.ldk`) в [folder].
  Future<void> _createLdk(String folder) async {
    final at = ref.read(mapCrosshairProvider);
    await LdkCreateDialog.createIn(
      context,
      _services,
      folder,
      at: at == null ? null : LandmarkLocation(latitude: at.latitude, longitude: at.longitude),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Exception catch (e) {
      _snack('Не удалось создать: $e');
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _askName(String title) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title),
    );
    final trimmed = name?.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _onMenu(ExplorerMenuAction action) async {
    setState(() => _menuOpen = false);
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
    backgroundColor: NewMarkerSheet.background,
    builder: (context) {
      const labels = {
        SortField.name: 'По имени',
        SortField.date: 'По дате',
        SortField.distanceFromScreenCenter: 'По расстоянию от центра',
        SortField.length: 'По длине',
        SortField.duration: 'По длительности',
        SortField.elevationGain: 'По набору высоты',
        SortField.area: 'По площади',
        SortField.maxElevation: 'По высоте',
        SortField.slope: 'По среднему уклону',
        SortField.speed: 'По скорости',
        SortField.calories: 'По калориям',
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
                        color: Theme.of(context).colorScheme.primary,
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
    backgroundColor: NewMarkerSheet.background,
    builder: (context) {
      const labels = {
        null: 'Все типы',
        LandmarkType.waypoint: 'Путевые точки',
        LandmarkType.set: 'Наборы точек',
        LandmarkType.route: 'Маршруты',
        LandmarkType.track: 'Треки',
        LandmarkType.area: 'Области',
        LandmarkType.circle: 'Круги',
        LandmarkType.text: 'Тексты',
        LandmarkType.ldkFile: 'Файлы меток',
      };
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final MapEntry(key: type, value: label) in labels.entries)
              ListTile(
                key: Key('filter_${type?.extension ?? 'all'}'),
                title: Text(label),
                trailing: current.onlyType == type
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
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
    final theme = Theme.of(context);
    final subtitle = ExplorerBreadcrumbs.of(
      place == null
          ? null
          : PlaceRoot(
              id: place.id,
              title: LocalLandmarksDrawer.titleOf(place, _deviceUsage),
              path: place.path,
              kind: place.kind,
            ),
      state.currentFolder,
    );
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _onBack,
      child: ItemHooks(
        onOpen: _openDetails,
        child: Builder(
          builder: (hooksContext) {
            // Меню открываются от контекста под хуками: действия находят их.
            _hooksContext = hooksContext;
            return Scaffold(
        floatingActionButton: selection.isActive
            ? null
            : FloatingActionButton(key: const Key('explorer_fab'), onPressed: _create, child: const Icon(Icons.add)),
        bottomNavigationBar: selection.isActive
            ? _selectionBar(theme, selection.count)
            : (_explorer.clipboard.isEmpty ? null : _clipboardBar(theme)),
        body: Column(
          children: [
            MapsAppBar(
              title: 'Локальные метки',
              subtitle: subtitle,
              onMenu: () => setState(() {
                _menuOpen = false;
                _drawerOpen = !_drawerOpen;
              }),
              onClose: () => Navigator.of(context).maybePop(),
              onMore: () => setState(() {
                _drawerOpen = false;
                _menuOpen = !_menuOpen;
              }),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        StorageBar(
                          key: const Key('explorer_storage'),
                          usage: _folderUsage,
                          caption: '${_explorer.allItems.length} файл. · ${foldersCaption(folders.length)}',
                        ),
                        const Divider(height: 1),
                        if (!_hasAccess) PermissionBanner(onActivate: _activate),
                        Expanded(child: _list(state, selection.isActive, folders, items)),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: LocalLandmarksDrawer(
                      bookmarkController: _services.bookmarkController,
                      onBookmark: _openBookmark,
                      isOpen: _drawerOpen,
                      places: _places,
                      currentPlace: place,
                      deviceUsage: _deviceUsage,
                      onPlace: _onPlace,
                      onClose: () => setState(() => _drawerOpen = false),
                    ),
                  ),
                  Positioned.fill(
                    child: ExplorerDropdownMenu(
                      isOpen: _menuOpen,
                      viewMode: state.viewMode,
                      onSelected: _onMenu,
                      onDismiss: () => setState(() => _menuOpen = false),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
          },
        ),
      ),
    );
  }

  /// «1 папка», «3 папки», «5 папок».
  static String foldersCaption(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'папка'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? 'папки' : 'папок');
    return '$n $word';
  }

  Widget _list(ExplorerState state, bool selecting, List<ExplorerFolderNode> folders, List<ExplorerItemNode> items) {
    if (state.isLoading || state.currentFolder == null) {
      return const Center(child: CircularProgressIndicator(key: Key('explorer_loading')));
    }
    if (state.nodes.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        key: const Key('explorer_empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text('Папка пуста', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _explorer.refresh,
      child: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + 88),
        children: [
          LocalLandmarksFolderList(
            folders: folders,
            onOpen: _explorer.openFolder,
            onMenu: (f) => FolderContextMenu.show(context, f),
          ),
          for (final d in ref.read(descriptorRegistryProvider).all)
            LandmarkTypeSection(
              descriptor: d,
              items: _sectionItems(d, items),
              viewMode: SectionActions.viewModeOf(_services, d),
              groupName: _groupName(state),
              dense: state.viewMode == ExplorerViewMode.list,
              selecting: selecting,
              isSelected: _explorer.selection.contains,
              onTap: _onItemTap,
              onLongPress: _onItemLongPress,
              onSectionMenu: () => SectionContextMenu.show(_hooksContext ?? context, d.type),
            ),
        ],
      ),
    );
  }

  /// Элементы секции [d] в её сортировке (не задана — порядок списка).
  List<LandmarkItem> _sectionItems(LandmarkTypeDescriptor d, List<ExplorerItemNode> items) {
    final list = [
      for (final n in items)
        if (n.item.type == d.type) n.item,
    ];
    final sort = SectionActions.sortOf(_services, d.type);
    if (sort == null) return list;
    final at = ref.read(mapCrosshairProvider);
    return sort.apply(list, center: at == null ? null : (latitude: at.latitude, longitude: at.longitude));
  }

  /// Имя открытой папки для карточек: название места в его корне.
  String _groupName(ExplorerState state) {
    final folder = state.currentFolder ?? '';
    final place = state.currentPlace;
    if (place != null && p.equals(place.path, folder)) return LocalLandmarksDrawer.titleOf(place, _deviceUsage);
    return p.basename(folder);
  }

  Future<void> _toClipboard({required bool cut}) async {
    final paths = _explorer.selection.snapshot();
    final ops = _services.explorerOperations;
    final result = cut ? await ops.cutSelected(paths) : await ops.copySelected(paths);
    _explorer.selection.deactivate();
    _snack('${cut ? 'Вырезано' : 'Скопировано'}: ${result.affectedCount}');
  }

  /// Вставка буфера в открытую папку (только внутри «Мои метки»).
  Future<void> _paste() async {
    final folder = _explorer.state.currentFolder;
    if (folder == null) return;
    final root = _services.paths.landmarks;
    if (!p.equals(root, folder) && !p.isWithin(root, folder)) return _snack(FolderContextActions.unavailable);
    final result = await _services.explorerOperations.pasteAll(folder);
    await _changed();
    _snack(result.success ? 'Вставлено: ${result.affectedCount}' : (result.errorMessage ?? 'Не всё вставлено'));
  }

  Widget _clipboardBar(ThemeData theme) {
    final clipboard = _explorer.clipboard;
    final entries = clipboard.entries;
    final what = entries.length == 1 ? '«${entries.single.originalName}»' : '${entries.length} шт.';
    return Material(
      key: const Key('explorer_clipboard_bar'),
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(clipboard.isCut ? Icons.content_cut : Icons.content_copy, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${clipboard.isCut ? 'Вырезано' : 'Скопировано'}: $what',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(key: const Key('clipboard_paste'), onPressed: _paste, child: const Text('ВСТАВИТЬ')),
              TextButton(
                key: const Key('clipboard_empty'),
                onPressed: () => setState(clipboard.empty),
                child: const Text('ОЧИСТИТЬ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(ThemeData theme, int count) => Material(
    key: const Key('explorer_selection_bar'),
    elevation: 8,
    color: theme.colorScheme.surface,
    child: SafeArea(
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(child: Text('Выбрано: $count', style: theme.textTheme.titleSmall)),
            IconButton(
              key: const Key('selection_copy'),
              tooltip: 'Копировать',
              icon: const Icon(Icons.content_copy),
              onPressed: count == 0 ? null : () => _toClipboard(cut: false),
            ),
            IconButton(
              key: const Key('selection_cut'),
              tooltip: 'Вырезать',
              icon: const Icon(Icons.content_cut),
              onPressed: count == 0 ? null : () => _toClipboard(cut: true),
            ),
            IconButton(
              key: const Key('selection_delete'),
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: count == 0 ? null : _deleteSelected,
            ),
            TextButton(
              key: const Key('selection_cancel'),
              onPressed: _explorer.selection.deactivate,
              child: const Text('ОТМЕНА'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Имя новой папки или файла; поле живёт столько же, сколько диалог.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
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
