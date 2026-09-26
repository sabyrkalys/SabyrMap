import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_icons.dart';
import '../../widgets/app_icon.dart';
import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../services/layer_manager.dart';
import '../services/offline_service.dart';
import '../state/map_layers_controller.dart';
import '../state/map_viewport.dart';

/// «1.5 МБ», «820 КБ», «0 Б».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

/// 🌐 online only / 💾 cache / 📦 offline file.
String storageModeLabel(StorageMode mode) => switch (mode) {
      StorageMode.onlineOnly => '🌐 Онлайн',
      StorageMode.onlineCache => '💾 Кэш',
      StorageMode.offlineRegion => '📦 Офлайн',
    };

/// Map catalog: online maps by provider, installed maps and saved areas.
/// With [pickOverlay] it only picks a source to lay over the map.
class AvailableMapsScreen extends ConsumerStatefulWidget {
  const AvailableMapsScreen({super.key, this.pickOverlay = false});

  final bool pickOverlay;

  @override
  ConsumerState<AvailableMapsScreen> createState() => _AvailableMapsScreenState();
}

class _AvailableMapsScreenState extends ConsumerState<AvailableMapsScreen> {
  List<OfflineRegionInfo> _regions = const [];

  @override
  void initState() {
    super.initState();
    _reloadRegions();
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

  Future<void> _addMap() async {
    final added = await showDialog<bool>(context: context, builder: (_) => const _AddMapDialog());
    if (added == true) await ref.read(catalogProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final mapState = ref.watch(mapLayersProvider);
    final providers = catalog.value ?? const <MapProvider>[];
    final online = providers.where((p) => p.id != CatalogRepository.localProviderId).toList();
    final installed = providers.firstWhereOrNull((p) => p.id == CatalogRepository.localProviderId);
    final isolatedIds = {
      for (final p in providers)
        if (p.isolated) ...p.sources.map((s) => s.id),
    };
    final baseIsolated = isolatedIds.contains(mapState.baseSourceId);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pickOverlay ? 'Добавить слой' : 'Доступные карты'),
          bottom: const TabBar(tabs: [Tab(text: 'Онлайн-карты'), Tab(text: 'Установленные карты')]),
        ),
        floatingActionButton: widget.pickOverlay
            ? null
            : FloatingActionButton(
                key: const Key('add_map_button'),
                onPressed: _addMap,
                child: const Icon(Icons.add),
              ),
        body: Builder(
          builder: (context) {
            final regions = _regions;
            Widget tile(MapSource source) => _SourceTile(
                  source: source,
                  cacheBytes: regions.where((r) => r.sourceId == source.id).fold(0, (sum, r) => sum + r.sizeBytes),
                  isolated: isolatedIds.contains(source.id),
                  baseIsolated: baseIsolated,
                  favorite: mapState.favoriteIds.contains(source.id),
                  pickOverlay: widget.pickOverlay,
                  onShow: () => _show(source),
                  onAddOverlay: () => _addOverlay(source),
                  onFavorite: () => ref.read(mapLayersProvider.notifier).toggleFavorite(source.id),
                  onClearCache: () => _clearCache(source, regions),
                  onSaveRegion: () => _saveRegion(source),
                );
            return Column(
              children: [
                _CacheIndicator(regions: regions),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        children: [
                          for (final provider in online)
                            ExpansionTile(
                              key: Key('provider_${provider.id}'),
                              title: Text(provider.name),
                              subtitle: provider.sources.every((s) => s.storageMode == StorageMode.onlineOnly)
                                  ? const Text('Только онлайн')
                                  : null,
                              children: [for (final source in provider.sources) tile(source)],
                            ),
                        ],
                      ),
                      ListView(
                        children: [
                          for (final source in installed?.sources ?? const <MapSource>[]) tile(source),
                          for (final region in regions)
                            ListTile(
                              key: Key('region_${region.id}'),
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
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Total size of saved areas, with a bar while some are still downloading.
class _CacheIndicator extends StatelessWidget {
  const _CacheIndicator({required this.regions});

  final List<OfflineRegionInfo> regions;

  @override
  Widget build(BuildContext context) {
    final total = regions.fold(0, (sum, r) => sum + r.sizeBytes);
    final downloading = regions.where((r) => !r.isComplete).toList();
    final progress = downloading.isEmpty
        ? null
        : downloading.fold(0.0, (sum, r) => sum + r.progress) / downloading.length / 100;
    return Padding(
      key: const Key('cache_indicator'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Кэш: ${formatBytes(total)}'),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          ],
        ],
      ),
    );
  }
}

enum _SourceAction { show, overlay, favorite, details, clearCache, saveRegion }

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.cacheBytes,
    required this.isolated,
    required this.baseIsolated,
    required this.favorite,
    required this.pickOverlay,
    required this.onShow,
    required this.onAddOverlay,
    required this.onFavorite,
    required this.onClearCache,
    required this.onSaveRegion,
  });

  final MapSource source;
  final int cacheBytes;
  final bool isolated;
  final bool baseIsolated;
  final bool favorite;
  final bool pickOverlay;
  final VoidCallback onShow;
  final VoidCallback onAddOverlay;
  final VoidCallback onFavorite;
  final VoidCallback onClearCache;
  final VoidCallback onSaveRegion;

  bool get _canOverlay => source.canBeOverlay && source.format == TileFormat.raster && !isolated && !baseIsolated;

  @override
  Widget build(BuildContext context) {
    final subtitle = cacheBytes > 0
        ? '${storageModeLabel(source.storageMode)} · ${formatBytes(cacheBytes)}'
        : storageModeLabel(source.storageMode);
    final thumbnail = source.thumbnailAsset;
    return ListTile(
      key: Key('source_${source.id}'),
      enabled: !pickOverlay || _canOverlay,
      leading: thumbnail != null
          ? Image.asset(thumbnail, width: 40, height: 40, fit: BoxFit.cover)
          : AppIcon(source.format == TileFormat.vector ? AppIcons.map : AppIcons.layers),
      title: Row(
        children: [
          Flexible(child: Text(source.name)),
          if (favorite) ...[const SizedBox(width: 6), const AppIcon(AppIcons.star, size: 16)],
        ],
      ),
      subtitle: Text(subtitle),
      onTap: pickOverlay ? (_canOverlay ? onAddOverlay : null) : onShow,
      trailing: pickOverlay
          ? null
          : PopupMenuButton<_SourceAction>(
              key: Key('source_menu_${source.id}'),
              onSelected: (action) => switch (action) {
                _SourceAction.show => onShow(),
                _SourceAction.overlay => onAddOverlay(),
                _SourceAction.favorite => onFavorite(),
                _SourceAction.details => showDialog<void>(context: context, builder: (_) => _DetailsDialog(source: source)),
                _SourceAction.clearCache => onClearCache(),
                _SourceAction.saveRegion => onSaveRegion(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: _SourceAction.show, child: Text('Показать')),
                PopupMenuItem(value: _SourceAction.overlay, enabled: _canOverlay, child: const Text('Добавить как слой')),
                CheckedPopupMenuItem(value: _SourceAction.favorite, checked: favorite, child: const Text('В избранное')),
                const PopupMenuItem(value: _SourceAction.details, child: Text('Детали')),
                if (source.storageMode != StorageMode.onlineOnly)
                  const PopupMenuItem(value: _SourceAction.clearCache, child: Text('Очистить кэш')),
                if (OfflineService.canSaveRegion(source))
                  const PopupMenuItem(value: _SourceAction.saveRegion, child: Text('Сохранить участок карты')),
              ],
            ),
    );
  }
}

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({required this.source});

  final MapSource source;

  @override
  Widget build(BuildContext context) {
    final style = source.styleUrl;
    final url = source.tileUrlTemplate ??
        (style == null ? '—' : (style.trimLeft().startsWith('{') ? 'Файл стиля JSON' : style));
    return AlertDialog(
      title: Text(source.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('URL: $url'),
          const SizedBox(height: 8),
          Text('Лицензия: ${source.attribution ?? '—'}'),
          const SizedBox(height: 8),
          Text('Масштаб: ${source.minZoom}–${source.maxZoom}'),
          const SizedBox(height: 8),
          Text(storageModeLabel(source.storageMode)),
        ],
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
