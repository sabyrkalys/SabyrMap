import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLngBounds;

import '../../app_icons.dart';
import '../../format_bytes.dart';
import '../../widgets/app_icon.dart';
import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../regions/region_downloads.dart';
import '../regions/server_region_dialog.dart';
import '../regions/server_region_service.dart';
import '../services/layer_manager.dart';
import '../services/offline_service.dart';
import '../services/tile_cache_stats.dart';
import '../state/map_layers_controller.dart';
import '../state/map_viewport.dart';

import 'available_maps/available_maps_models.dart';
import 'available_maps/device_storage.dart';
import 'available_maps/dropdown_menu.dart';
import 'available_maps/map_card.dart';
import 'available_maps/map_card_menu.dart';
import 'available_maps/map_source_accordion.dart';
import 'available_maps/maps_app_bar.dart';
import 'available_maps/maps_dialogs.dart';
import 'available_maps/side_drawer.dart';
import 'available_maps/storage_bar.dart';

export '../../format_bytes.dart' show formatBytes;

/// 🌐 online only / 💾 cache / 📦 offline file.
String storageModeLabel(StorageMode mode) => switch (mode) {
      StorageMode.onlineOnly => '🌐 Онлайн',
      StorageMode.onlineCache => '💾 Кэш',
      StorageMode.offlineRegion => '📦 Офлайн',
    };

/// Map catalog as groups of map cards: OpenStreetMap, our server's maps
/// (under «GOOGLE MAPS» for now), installed maps and saved areas. With
/// [pickOverlay] it only picks a source to lay over the map; with
/// [saveBaseRegion] it opens «Сохранить участок карты» for the map on screen
/// (the maps menu item).
class AvailableMapsScreen extends ConsumerStatefulWidget {
  const AvailableMapsScreen({super.key, this.pickOverlay = false, this.saveBaseRegion = false});

  final bool pickOverlay;
  final bool saveBaseRegion;

  @override
  ConsumerState<AvailableMapsScreen> createState() => _AvailableMapsScreenState();
}

class _AvailableMapsScreenState extends ConsumerState<AvailableMapsScreen> {
  List<OfflineRegionInfo> _regions = const [];
  Map<String, bool> _openGroups = const {'google': true};
  bool _isDrawerOpen = false;
  bool _isDropdownOpen = false;
  MapsSection _section = MapsSection.available;
  MapsFilter _filter = const MapsFilter();

  @override
  void initState() {
    super.initState();
    _reloadRegions();
    if (widget.saveBaseRegion) WidgetsBinding.instance.addPostFrameCallback((_) => _saveBaseRegion());
  }

  Future<void> _saveBaseRegion() async {
    final baseId = ref.read(mapLayersProvider).baseSourceId;
    final providers = await ref.read(catalogProvider.future);
    final base = providers.expand((p) => p.sources).firstWhereOrNull((s) => s.id == baseId);
    if (!mounted) return;
    if (base == null || !(ServerRegionService.canDownload(base) || OfflineService.canSaveRegion(base))) {
      _message('Для карты на экране сохранение участка недоступно — выберите карту «Сервер карт»');
      return;
    }
    await _saveRegion(base);
  }

  Future<void> _reloadRegions() async {
    List<OfflineRegionInfo> regions;
    try {
      regions = await ref.read(offlineServiceProvider).listRegions();
    } catch (_) {
      regions = const [];
    }
    if (mounted) setState(() => _regions = regions);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on LayerException catch (e) {
      _message(e.message);
    } on OfflineException catch (e) {
      _message(e.message);
    } on CatalogException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _show(MapSource source) => _run(() async {
        final result = await ref.read(mapLayersProvider.notifier).setBase(source);
        if (!result.ok) _message(result.problems.join('\n'));
        if (mounted) Navigator.of(context).pop();
      });

  Future<void> _addOverlay(MapSource source) => _run(() async {
        await ref.read(mapLayersProvider.notifier).addOverlay(source);
        if (widget.pickOverlay && mounted) Navigator.of(context).pop(true);
      });

  Future<void> _clearCache(MapSource source, List<OfflineRegionInfo> regions) => _run(() async {
        final own = regions.where((r) => r.sourceId == source.id).toList();
        if (own.isEmpty) {
          _message('Для этой карты нет сохранённых участков');
          return;
        }
        for (final region in own) {
          await ref.read(offlineServiceProvider).deleteRegion(region.id);
        }
        await _reloadRegions();
      });

  Future<void> _saveRegion(MapSource source) async {
    final viewport = await ref.read(mapViewportProvider.notifier).read();
    if (!mounted) return;
    if (viewport == null) {
      _message('Карта ещё не готова');
      return;
    }
    if (ServerRegionService.canDownload(source)) {
      await _saveServerRegion(source, viewport.bounds);
      return;
    }
    final request = await showDialog<_SaveRegionRequest>(
      context: context,
      builder: (_) => _SaveRegionDialog(source: source, currentZoom: viewport.zoom),
    );
    if (request == null) return;
    await _run(() async {
      await ref.read(offlineServiceProvider).createRegion(
            source: source,
            bounds: viewport.bounds,
            minZoom: request.minZoom,
            maxZoom: request.maxZoom,
            name: request.name,
            onError: _message,
          );
      _message('Участок «${request.name}» сохраняется');
      await _reloadRegions();
    });
  }

  /// Our server cuts the area; it is downloaded in the background and
  /// shows up under «Установленные карты».
  Future<void> _saveServerRegion(MapSource source, LatLngBounds bounds) async {
    final request = await showDialog<ServerRegionRequest>(
      context: context,
      builder: (_) => ServerRegionDialog(source: source, bounds: bounds),
    );
    if (request == null) return;
    ref.read(regionDownloadsProvider.notifier).start(
          source: source,
          bounds: bounds,
          maxZoom: request.maxZoom,
          name: request.name,
          wifiOnly: request.wifiOnly,
        );
    _message('Участок «${request.name}» скачивается — ход загрузки в «Установленные карты»');
  }

  Future<void> _deleteLocalRegion(MapSource source) => _run(() async {
        if (ref.read(mapLayersProvider).baseSourceId == source.id) {
          _message('Эта карта сейчас на экране — сначала выберите другую');
          return;
        }
        await ref.read(catalogRepositoryProvider).deleteLocalRegion(source.id);
        await ref.read(catalogProvider.notifier).reload();
      });

  Future<void> _addMap() async {
    final added = await showDialog<bool>(context: context, builder: (_) => const _AddMapDialog());
    if (added == true) await ref.read(catalogProvider.notifier).reload();
  }

  void _toggleGroup(String id) => setState(() => _openGroups = {..._openGroups, id: !(_openGroups[id] ?? false)});

  void _toggleDrawer() => setState(() {
    _isDrawerOpen = !_isDrawerOpen;
    _isDropdownOpen = false;
  });

  void _toggleDropdown() => setState(() {
    _isDropdownOpen = !_isDropdownOpen;
    _isDrawerOpen = false;
  });

  void _selectSection(MapsSection section) => setState(() {
    _section = section;
    _isDrawerOpen = false;
  });

  Future<void> _onMenuAction(MapsMenuAction action) async {
    setState(() => _isDropdownOpen = false);
    switch (action) {
      case MapsMenuAction.filter:
        final filter = await showDialog<MapsFilter>(
          context: context,
          builder: (_) => MapsFilterDialog(initial: _filter),
        );
        if (filter != null && mounted) setState(() => _filter = filter);
      case MapsMenuAction.settings:
        await showDialog<void>(context: context, builder: (_) => const MapsSettingsDialog());
      case MapsMenuAction.help:
        await showDialog<void>(context: context, builder: (_) => const MapsHelpDialog());
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAdd = !widget.pickOverlay && _section == MapsSection.available;
    return Scaffold(
      floatingActionButton: showAdd
          ? FloatingActionButton(key: const Key('add_map_button'), onPressed: _addMap, child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          MapsAppBar(
            title: widget.pickOverlay ? 'Добавить слой' : 'Онлайн-карты',
            subtitle: _section.label,
            onMenu: _toggleDrawer,
            onClose: () => Navigator.of(context).maybePop(),
            onMore: _toggleDropdown,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _section == MapsSection.available
                      ? _mapList(bottomInset: MediaQuery.viewPaddingOf(context).bottom + (showAdd ? 88 : 16))
                      : const Center(
                          child: Card(
                            child: Padding(padding: EdgeInsets.all(24), child: Text('Раздел в разработке')),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: SideDrawer(
                    isOpen: _isDrawerOpen,
                    activeSection: _section,
                    storage: ref.watch(deviceStorageProvider).value,
                    folders: mockDeviceFolders,
                    onSectionSelected: _selectSection,
                    onClose: () => setState(() => _isDrawerOpen = false),
                  ),
                ),
                Positioned.fill(
                  child: MapsDropdownMenu(
                    isOpen: _isDropdownOpen,
                    onSelected: _onMenuAction,
                    onDismiss: () => setState(() => _isDropdownOpen = false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCardMenu(
    MapSource source, {
    required bool active,
    required bool favorite,
    required bool canOverlay,
    required bool canClearCache,
    required int sizeBytes,
    required int cachedBytes,
    required String sourceName,
    LocalMapInfo? local,
  }) async {
    final action = await showMapCardMenu(
      context,
      mapName: source.name,
      active: active,
      favorite: favorite,
      canOverlay: canOverlay,
      canClearCache: canClearCache,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case MapCardAction.remove:
        await _remove(source);
      case MapCardAction.show:
        await _show(source);
      case MapCardAction.addOverlay:
        await _addOverlay(source);
      case MapCardAction.favorite:
        await ref.read(mapLayersProvider.notifier).toggleFavorite(source.id);
        _message(favorite ? '«${source.name}» убрана из избранных' : '«${source.name}» сохранена в избранные');
      case MapCardAction.details:
        await showDialog<void>(
          context: context,
          builder: (_) => _DetailsDialog(
            source: source,
            sourceName: sourceName,
            sizeBytes: sizeBytes,
            cachedBytes: cachedBytes,
            local: local,
          ),
        );
      case MapCardAction.clearCache:
        await _confirmClearCache(source, sizeBytes);
    }
  }

  /// «Убрать»: takes an overlay off the map. The base map stays until
  /// another one is shown, so the screen is never left without a map.
  Future<void> _remove(MapSource source) => _run(() async {
        if (ref.read(mapLayersProvider).baseSourceId == source.id) {
          _message('Это основная карта на экране — сначала покажите другую');
          return;
        }
        await ref.read(mapLayersProvider.notifier).removeOverlay(source.id);
        _message('«${source.name}» убрана с экрана');
      });

  /// «Очистить кэш»: deletes a downloaded region, or the saved areas of an
  /// online map, after a confirmation.
  Future<void> _confirmClearCache(MapSource source, int sizeBytes) async {
    final downloaded = source.id.startsWith(CatalogRepository.localRegionPrefix);
    if (downloaded && ref.read(mapLayersProvider).baseSourceId == source.id) {
      _message('Эта карта сейчас на экране — сначала выберите другую');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить кэш'),
        content: Text(
          downloaded
              ? 'Удалить скачанную карту «${source.name}» (${formatBytes(sizeBytes)}) с телефона?'
              : 'Удалить сохранённые участки карты «${source.name}» (${formatBytes(sizeBytes)})?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          TextButton(
            key: const Key('clear_cache_confirm'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (downloaded) {
      await _deleteLocalRegion(source);
    } else {
      await _clearCache(source, _regions);
    }
    _message('Кэш очищен');
  }

  Widget _mapList({required double bottomInset}) {
    final catalog = ref.watch(catalogProvider);
    final mapState = ref.watch(mapLayersProvider);
    final downloads = ref.watch(regionDownloadsProvider);
    final localInfo = ref.watch(localMapInfoProvider).value ?? const <String, LocalMapInfo>{};
    final providers = catalog.value ?? const <MapProvider>[];
    final installed = providers.firstWhereOrNull((p) => p.id == CatalogRepository.localProviderId);
    final sourcesById = {for (final p in providers) ...{for (final s in p.sources) s.id: s}};
    final isolatedIds = {
      for (final p in providers)
        if (p.isolated) ...p.sources.map((s) => s.id),
    };
    final baseIsolated = isolatedIds.contains(mapState.baseSourceId);
    final regions = _regions;
    final tileCache = ref.watch(tileCacheStatsProvider).value ?? TileCacheStats.empty;
    int cacheOf(MapSource source) =>
        regions.where((r) => r.sourceId == source.id).fold(0, (sum, r) => sum + r.sizeBytes);

    // Online maps by group, then everything installed goes to the group of
    // the map it came from (or «Свои карты» when that is unknown).
    final online = groupProviders(providers);
    final groupOfSource = {
      for (final g in online)
        for (final s in g.sources) s.id: g.id,
    };
    String groupFor(String? sourceId) => groupOfSource[sourceId] ?? ownGroupId;
    final titles = {for (final g in online) g.id: g.title, ownGroupId: ownGroupTitle};

    /// [sizeBytes]: disk size of an installed map; online maps show what
    /// MapLibre's tile cache holds for them.
    Widget card(MapSource source, {int? sizeBytes, MapSource? origin}) {
      final cached = sizeBytes == null ? tileCache.bytesOf([source.id]) : 0;
      final canOverlay = source.canBeOverlay &&
          source.format == TileFormat.raster &&
          !isolatedIds.contains(source.id) &&
          !baseIsolated;
      final favorite = mapState.favoriteIds.contains(source.id);
      return _SourceCard(
        source: source,
        sizeBytes: sizeBytes ?? cached,
        cached: sizeBytes == null,
        kind: mapKindOf(origin ?? source),
        canOverlay: canOverlay,
        favorite: favorite,
        selected: mapState.baseSourceId == source.id,
        pickOverlay: widget.pickOverlay,
        onTap: widget.pickOverlay ? () => _addOverlay(source) : () => _show(source),
        onMenu: () => _openCardMenu(
          source,
          active: mapState.baseSourceId == source.id || mapState.overlays.any((o) => o.sourceId == source.id),
          favorite: favorite,
          canOverlay: canOverlay,
          // Downloaded regions and saved areas; never the user's own files.
          canClearCache: source.id.startsWith(CatalogRepository.localRegionPrefix) ||
              (!source.id.startsWith('local-') && cacheOf(source) > 0),
          sizeBytes: sizeBytes ?? cacheOf(source),
          cachedBytes: cached,
          sourceName: titles[groupFor((origin ?? source).id)]!,
          local: localInfo[source.id],
        ),
      );
    }

    Widget regionTile(OfflineRegionInfo region) => ListTile(
          key: Key('region_${region.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const AppIcon(AppIcons.download),
          title: Text(region.name),
          subtitle: Text(
            region.isComplete
                ? formatBytes(region.sizeBytes)
                : '${formatBytes(region.sizeBytes)} · ${region.progress.toStringAsFixed(0)}%',
          ),
          trailing: IconButton(
            key: Key('region_delete_${region.id}'),
            icon: const AppIcon(AppIcons.trash),
            onPressed: () => _run(() async {
              await ref.read(offlineServiceProvider).deleteRegion(region.id);
              await _reloadRegions();
            }),
          ),
        );

    final onlineCards = <String, List<Widget>>{};
    for (final g in online) {
      for (final s in g.sources) {
        if (_filter.accepts(s, cacheOf(s))) (onlineCards[g.id] ??= []).add(card(s));
      }
    }
    final downloaded = <String, List<Widget>>{};
    final downloadedBytes = <String, int>{};
    void addDownloaded(String groupId, Widget child, int bytes) {
      (downloaded[groupId] ??= []).add(child);
      downloadedBytes[groupId] = (downloadedBytes[groupId] ?? 0) + bytes;
    }

    if (!widget.pickOverlay) {
      for (final download in downloads) {
        addDownloaded(
          groupFor(download.sourceId),
          _RegionDownloadTile(
            download: download,
            onCancel: () => ref.read(regionDownloadsProvider.notifier).cancel(download.key),
            onDismiss: () => ref.read(regionDownloadsProvider.notifier).dismiss(download.key),
          ),
          0,
        );
      }
    }
    for (final source in installed?.sources ?? const <MapSource>[]) {
      final info = localInfo[source.id];
      final origin = sourcesById[info?.originSourceId];
      if (!_filter.accepts(origin ?? source, 1)) continue;
      final bytes = info?.sizeBytes ?? 0;
      addDownloaded(groupFor(origin?.id), card(source, sizeBytes: bytes, origin: origin), bytes);
    }
    if (!widget.pickOverlay) {
      for (final region in regions) {
        final source = sourcesById[region.sourceId];
        if (_filter.onlySatellite && (source == null || !_filter.accepts(source, 1))) continue;
        addDownloaded(groupFor(region.sourceId), regionTile(region), region.sizeBytes);
      }
    }

    final groupIds = [...online.map((g) => g.id), ownGroupId];
    final groups = [
      for (final id in groupIds)
        if ((onlineCards[id] ?? const []).isNotEmpty || (downloaded[id] ?? const []).isNotEmpty)
          MapSourceAccordion(
            key: Key('group_$id'),
            id: id,
            title: titles[id]!,
            subtitle: [
              if (tileCache.bytesOf([...?online.firstWhereOrNull((g) => g.id == id)?.sources.map((s) => s.id)])
                  case final bytes when bytes > 0)
                'кэш ≈ ${formatBytes(bytes)}',
              if ((downloadedBytes[id] ?? 0) > 0) 'скачано ${formatBytes(downloadedBytes[id]!)}',
              for (final g in online.where((g) => g.id == id))
                for (final p in g.providers)
                  if (p.attribution case final attribution?) attribution,
              if (downloaded[id] == null &&
                  online.where((g) => g.id == id).expand((g) => g.sources).every(
                        (s) => s.storageMode == StorageMode.onlineOnly,
                      ))
                'Только онлайн',
            ].join(' · '),
            isOpen: _openGroups[id] ?? false,
            onToggle: () => _toggleGroup(id),
            children: [
              ...?onlineCards[id],
              if (downloaded[id] case final items?) ...[
                _SectionLabel(key: Key('downloaded_label_$id'), text: 'Скачанные'),
                ...items,
              ],
            ],
          ),
    ];

    final cacheTotal = tileCache.bytesByTemplate.values.fold(0, (sum, b) => sum + b);
    final total = cacheTotal > 0 ? cacheTotal : regions.fold(0, (sum, r) => sum + r.sizeBytes);
    final downloading = regions.where((r) => !r.isComplete).toList();
    final progress = downloading.isEmpty
        ? null
        : downloading.fold(0.0, (sum, r) => sum + r.progress) / downloading.length / 100;

    return Column(
      children: [
        StorageBar(
          key: const Key('cache_indicator'),
          usage: ref.watch(deviceStorageProvider).value,
          caption: 'Кэш: ${formatBytes(total)}',
          onSettings: () => _onMenuAction(MapsMenuAction.settings),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          ),
        const Divider(height: 1),
        Expanded(
          child: groups.isEmpty && _filter.isActive
              ? const Center(child: Text('Нет карт, подходящих под фильтр'))
              : ListView(padding: EdgeInsets.only(bottom: bottomInset), children: groups),
        ),
      ],
    );
  }
}

/// «Скачанные» above a group's installed maps.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A catalog map as a [MapCard]: tap shows it (or adds it as a layer when
/// picking an overlay), ⋮ opens [onMenu].
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.sizeBytes,
    required this.cached,
    required this.kind,
    required this.canOverlay,
    required this.favorite,
    required this.selected,
    required this.pickOverlay,
    required this.onTap,
    required this.onMenu,
  });

  final MapSource source;

  /// What MapLibre's cache holds for an online map ([cached]), or the disk
  /// size of an installed one.
  final int sizeBytes;
  final bool cached;
  final MapKind kind;
  final bool canOverlay;
  final bool favorite;
  final bool selected;
  final bool pickOverlay;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return MapCard(
      key: Key('source_${source.id}'),
      name: source.name,
      caption: sizeBytes <= 0 ? 'Нет' : (cached ? '≈ ${formatBytes(sizeBytes)} в кэше' : formatBytes(sizeBytes)),
      kind: kind,
      thumbnailAsset: source.thumbnailAsset,
      favorite: favorite,
      selected: selected,
      enabled: !pickOverlay || canOverlay,
      onTap: onTap,
      menu: pickOverlay
          ? null
          : IconButton(
              key: Key('source_menu_${source.id}'),
              icon: const AppIcon(AppIcons.dotsVertical, color: Colors.white),
              onPressed: onMenu,
            ),
    );
  }
}

/// A server region on its way: stage, progress, cancel / dismiss.
class _RegionDownloadTile extends StatelessWidget {
  const _RegionDownloadTile({required this.download, required this.onCancel, required this.onDismiss});

  final RegionDownload download;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final running = download.state == RegionDownloadState.running;
    final fraction = download.fraction;
    return ListTile(
      key: Key('region_download_${download.key}'),
      leading: const AppIcon(AppIcons.download),
      title: Text(download.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            download.label,
            if (running && fraction != null) '${(fraction * 100).toStringAsFixed(0)}%',
          ].join(' · ')),
          if (download.error != null)
            Text(download.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: fraction?.clamp(0.0, 1.0)),
          ],
        ],
      ),
      trailing: IconButton(
        key: Key('region_download_action_${download.key}'),
        tooltip: running ? 'Отменить' : 'Убрать из списка',
        icon: Icon(running ? Icons.close : Icons.check),
        onPressed: running ? onCancel : onDismiss,
      ),
    );
  }
}

/// «Детали»: source, size, date, coverage and tile format of a map. Server
/// addresses are deliberately left out.
class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({
    required this.source,
    required this.sourceName,
    required this.sizeBytes,
    required this.cachedBytes,
    this.local,
  });

  final MapSource source;

  /// Group title and attribution of the map (or of the map it came from).
  final String sourceName;
  /// Disk size of an installed map, or the saved areas of an online one.
  final int sizeBytes;

  /// MapLibre's tile cache for the map's tile sets (shared ones included).
  final int cachedBytes;
  final LocalMapInfo? local;

  @override
  Widget build(BuildContext context) {
    final local = this.local;
    final created = local?.createdAt?.toLocal();
    final bbox = local?.bbox;
    String two(int v) => v.toString().padLeft(2, '0');
    String coord(double v) => v.toStringAsFixed(3);
    final rows = <(String, String)>[
      ('Источник', [sourceName, if (source.attribution case final a?) a].join(' · ')),
      if (source.storageMode == StorageMode.offlineRegion)
        ('Размер', sizeBytes > 0 ? formatBytes(sizeBytes) : '—')
      else ...[
        (
          'В кэше',
          cachedBytes > 0 ? '≈ ${formatBytes(cachedBytes)} (тайлы, общие с другими картами, входят и в их кэш)' : 'Нет',
        ),
        if (sizeBytes > 0) ('Сохранённые участки', formatBytes(sizeBytes)),
      ],
      (
        'Обновлено',
        created != null
            ? '${two(created.day)}.${two(created.month)}.${created.year}'
            : (source.version != null ? 'версия ${source.version}' : '—'),
      ),
      (
        'Покрытие',
        [
          if (bbox != null) '${coord(bbox[1])}…${coord(bbox[3])} с. ш., ${coord(bbox[0])}…${coord(bbox[2])} в. д.',
          'масштаб ${source.minZoom}–${local?.maxZoom ?? source.maxZoom}',
        ].join(', '),
      ),
      ('Формат тайлов', '${source.format == TileFormat.vector ? 'Векторные' : 'Растровые'} · ${storageModeLabel(source.storageMode)}'),
    ];
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(source.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows) ...[
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть'))],
    );
  }
}

class _SaveRegionRequest {
  const _SaveRegionRequest(this.name, this.minZoom, this.maxZoom);

  final String name;
  final double minZoom;
  final double maxZoom;
}

/// Saves the area visible on the map; the user names it and picks zooms.
class _SaveRegionDialog extends StatefulWidget {
  const _SaveRegionDialog({required this.source, required this.currentZoom});

  final MapSource source;
  final double currentZoom;

  @override
  State<_SaveRegionDialog> createState() => _SaveRegionDialogState();
}

class _SaveRegionDialogState extends State<_SaveRegionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.source.name);
  late RangeValues _zooms;

  double get _max => widget.source.maxZoom.toDouble();
  double get _min => widget.source.minZoom.toDouble();

  @override
  void initState() {
    super.initState();
    final start = widget.currentZoom.floorToDouble().clamp(_min, _max);
    _zooms = RangeValues(start, _max);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сохранить участок карты'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('save_region_name'), controller: _name, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 16),
          Text('Масштаб: ${_zooms.start.round()}–${_zooms.end.round()}'),
          RangeSlider(
            min: _min,
            max: _max,
            divisions: (_max - _min).round().clamp(1, 30),
            values: _zooms,
            onChanged: (v) => setState(() => _zooms = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        TextButton(
          key: const Key('save_region_confirm'),
          onPressed: () => Navigator.of(context).pop(_SaveRegionRequest(_name.text.trim(), _zooms.start, _zooms.end)),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// «+»: a style by URL, or a style JSON file.
class _AddMapDialog extends ConsumerStatefulWidget {
  const _AddMapDialog();

  @override
  ConsumerState<_AddMapDialog> createState() => _AddMapDialogState();
}

class _AddMapDialogState extends ConsumerState<_AddMapDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _addUrl() async {
    try {
      await ref.read(catalogRepositoryProvider).addStyleUrl(name: _name.text, url: _url.text);
      if (mounted) Navigator.of(context).pop(true);
    } on CatalogException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _pickJson() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    try {
      await ref.read(catalogRepositoryProvider).importStyleFile(path);
      if (mounted) Navigator.of(context).pop(true);
    } on CatalogException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить карту'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('add_map_name'), controller: _name, decoration: const InputDecoration(labelText: 'Название')),
          TextField(
            key: const Key('add_map_url'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: 'Style URL', errorText: _error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(key: const Key('add_map_json'), onPressed: _pickJson, child: const Text('JSON-файл')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        TextButton(key: const Key('add_map_confirm'), onPressed: _addUrl, child: const Text('Добавить')),
      ],
    );
  }
}
