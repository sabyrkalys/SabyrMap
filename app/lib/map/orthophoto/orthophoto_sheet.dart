import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_icons.dart';
import '../../format_bytes.dart';
import '../../widgets/app_icon.dart';
import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../screens/available_maps/map_card_menu.dart';
import '../services/layer_manager.dart';
import '../services/offline_service.dart';
import '../state/map_layers_controller.dart';

/// Ортофотоплан — любой `.mbtiles` из папки ортофотопланов телефона
/// (`mediafile/orthophoto`), как бы он ни назывался: одна территория на файл.
bool isOrthophoto(MapSource source) => source.id.startsWith(CatalogRepository.orthophotoPrefix);

/// Ортофотопланы каталога, по имени.
List<MapSource> orthophotosOf(List<MapProvider> providers) => [
  for (final provider in providers)
    for (final source in provider.sources)
      if (isOrthophoto(source)) source,
]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Шторка «Ортофотопланы» с главного экрана: «Показывать все» — все
/// территории разом поверх карты; ниже список, нажатие открывает то же меню,
/// что в «Доступных картах» («Показать», «Добавить как слой», «Убрать»).
/// При открытии папка перечитывается: новые файлы появляются сами.
Future<void> showOrthophotoSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const OrthophotoSheet(),
);

class OrthophotoSheet extends ConsumerStatefulWidget {
  const OrthophotoSheet({super.key});

  static const Color _text = Color(0xFF212121);
  static const Color _secondary = Color(0xFF757575);
  static const Color _accent = Color(0xFF00897B);

  @override
  ConsumerState<OrthophotoSheet> createState() => _OrthophotoSheetState();
}

class _OrthophotoSheetState extends ConsumerState<OrthophotoSheet> {
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    // Новые территории, положенные в папку, появляются без перезапуска.
    Future.microtask(() async {
      try {
        await ref.read(mapLayersProvider.notifier).refreshOrthophotos();
      } catch (_) {}
    });
  }

  Future<void> _setAll(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _switching = true);
    try {
      final result = await ref.read(mapLayersProvider.notifier).setOrthophotosOn(on);
      if (!result.ok) messenger.showSnackBar(SnackBar(content: Text(result.problems.join('\n'))));
    } on LayerException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final layers = ref.watch(mapLayersProvider);
    final sizes = ref.watch(localMapInfoProvider).value ?? const <String, LocalMapInfo>{};
    final maps = orthophotosOf(catalog.value ?? const []);

    String stateOf(MapSource source) {
      if (layers.baseSourceId == source.id) return 'на экране';
      if (layers.overlays.any((l) => l.sourceId == source.id)) return 'слой';
      if (layers.orthophotosOn) return 'показан';
      return '';
    }

    return Material(
      key: const Key('orthophoto_sheet'),
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Ортофотопланы',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: OrthophotoSheet._text),
                ),
              ),
              SwitchListTile(
                key: const Key('orthophoto_all'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Показывать все', style: TextStyle(fontSize: 16, color: OrthophotoSheet._text)),
                subtitle: Text(
                  maps.isEmpty ? 'Нет файлов' : 'Территорий: ${maps.length} — каждая там, где есть снимок',
                  style: const TextStyle(fontSize: 13, color: OrthophotoSheet._secondary),
                ),
                activeThumbColor: OrthophotoSheet._accent,
                value: layers.orthophotosOn,
                onChanged: _switching || (maps.isEmpty && !layers.orthophotosOn) ? null : _setAll,
              ),
              const Divider(height: 1),
              if (catalog.isLoading && maps.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (maps.isEmpty)
                const Padding(
                  key: Key('orthophoto_empty'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Ортофотопланов нет. Положите файлы .mbtiles в папку телефона '
                    'Android/data/…/files/mediafile/orthophoto — каждый файл станет территорией.',
                    style: TextStyle(fontSize: 14, color: OrthophotoSheet._secondary),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final source in maps)
                        ListTile(
                          key: Key('orthophoto_${source.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: const AppIcon(AppIcons.drone, size: 24, color: Color(0xFF333333)),
                          ),
                          title: Text(source.name, style: const TextStyle(fontSize: 16, color: OrthophotoSheet._text)),
                          subtitle: Text(
                            [
                              if (sizes[source.id] case final info?) formatBytes(info.sizeBytes),
                              if (stateOf(source) case final state when state.isNotEmpty) state,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 13, color: OrthophotoSheet._secondary),
                          ),
                          trailing: const Icon(Icons.more_vert),
                          onTap: () => _openMenu(context, source),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('orthophoto_close'),
                  style: TextButton.styleFrom(foregroundColor: OrthophotoSheet._accent),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, MapSource source) async {
    final layers = ref.read(mapLayersProvider);
    final active = layers.baseSourceId == source.id || layers.overlays.any((l) => l.sourceId == source.id);
    final action = await showMapCardMenu(
      context,
      mapName: source.name,
      active: active,
      favorite: layers.favoriteIds.contains(source.id),
      canOverlay: source.canBeOverlay,
      canClearCache: false,
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(mapLayersProvider.notifier);
    void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      switch (action) {
        case MapCardAction.show:
          final result = await notifier.setBase(source);
          if (!result.ok) return say(result.problems.join('\n'));
          navigator.pop();
          say('«${source.name}» на экране');
        case MapCardAction.addOverlay:
          await notifier.addOverlay(source);
          navigator.pop();
          say('«${source.name}» добавлен как слой');
        case MapCardAction.remove:
          if (ref.read(mapLayersProvider).baseSourceId == source.id) {
            return say('Это основная карта на экране — сначала покажите другую');
          }
          await notifier.removeOverlay(source.id);
          say('«${source.name}» убран с экрана');
        case MapCardAction.favorite:
          await notifier.toggleFavorite(source.id);
        case MapCardAction.details:
          if (!context.mounted) return;
          final size = ref.read(localMapInfoProvider).value?[source.id]?.sizeBytes;
          await showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text(source.name),
              content: Text(
                [
                  'Своя карта, растровые тайлы',
                  if (size != null) 'Размер: ${formatBytes(size)}',
                  'Файл: ${source.tileUrlTemplate?.replaceFirst('mbtiles://', '') ?? '—'}',
                ].join('\n'),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Закрыть'))],
            ),
          );
        case MapCardAction.clearCache:
          return;
      }
    } on LayerException catch (e) {
      say(e.message);
    } on OfflineException catch (e) {
      say(e.message);
    } on CatalogException catch (e) {
      say(e.message);
    }
  }
}
