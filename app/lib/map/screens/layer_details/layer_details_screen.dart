import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../base/world_base_map.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';
import '../../services/tile_cache_stats.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';
import '../on_screen/layer_context_menu.dart';
import 'layer_details_model.dart';
import 'layer_details_preview.dart';
import 'layer_details_section.dart';

/// «Детали слоя»: превью, ИНФОРМАЦИЯ, ПРОЕКЦИЯ и ФАЙЛЫ карты [sourceId]
/// (или всех ортофотопланов — [MapStateNotifier.orthophotosKey]).
class LayerDetailsScreen extends ConsumerWidget {
  const LayerDetailsScreen({super.key, required this.sourceId, this.groupTitle, this.layerMenuId});

  final String sourceId;

  /// Подзаголовок группы, как в «Доступных картах»; по умолчанию — имя поставщика.
  final String? groupTitle;

  /// Слой «Карт на экране», чьё меню открывает ⋮; null — без ⋮.
  final String? layerMenuId;

  static Future<void> show(BuildContext context, String sourceId, {String? groupTitle, String? layerMenuId}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LayerDetailsScreen(sourceId: sourceId, groupTitle: groupTitle, layerMenuId: layerMenuId),
      ));

  LayerDetailsModel? _model(
    List<MapProvider> providers,
    Map<String, LocalMapInfo> local,
    TileCacheStats cache,
    String? worldPath,
  ) {
    if (sourceId == MapStateNotifier.worldKey) {
      final file = worldPath == null ? null : File(worldPath);
      return LayerDetailsModelBuilder.world(
        path: worldPath,
        sizeBytes: file != null && file.existsSync() ? file.lengthSync() : 0,
      );
    }
    if (sourceId == MapStateNotifier.orthophotosKey) {
      return LayerDetailsModelBuilder.orthophotos(
        sources: [
          for (final p in providers)
            if (p.id == CatalogRepository.orthophotoProviderId) ...p.sources,
        ],
        local: local,
      );
    }
    final entry = catalogIndex(providers)[sourceId];
    if (entry == null) return null;
    return LayerDetailsModelBuilder.fromSource(
      source: entry.source,
      provider: entry.provider,
      local: local[sourceId],
      cachedBytes: cache.bytesOf([sourceId]),
      groupTitle: groupTitle,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(catalogProvider).value ?? const <MapProvider>[];
    final local = ref.watch(localMapInfoProvider).value ?? const <String, LocalMapInfo>{};
    final cache = ref.watch(tileCacheStatsProvider).value ?? TileCacheStats.empty;
    final model = _model(providers, local, cache, ref.watch(worldBaseMapPathProvider).value);
    final layerMenuId = this.layerMenuId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model?.groupTitle ?? 'Карта',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
            ),
            Text(
              model?.displayName ?? sourceId,
              key: const Key('details_subtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('details_close'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (layerMenuId != null)
            IconButton(
              key: const Key('details_menu'),
              icon: const Icon(Icons.more_vert),
              onPressed: () => LayerContextMenu.show(context, layerMenuId),
            ),
        ],
      ),
      body: model == null
          ? const Center(child: Text('Карта не найдена в каталоге', style: TextStyle(color: Color(0xFF757575))))
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayerDetailsPreview(source: model.previewSource),
                  const SizedBox(height: 6),
                  LayerDetailsSection(
                    title: 'Информация',
                    fields: [
                      LayerDetailsFieldRow(label: 'Имя', value: model.info.name),
                      LayerDetailsFieldRow(label: 'Тип', value: model.info.type),
                      LayerDetailsFieldRow(label: 'Добавить как слой', value: model.info.canBeAddedAsLayer ? 'Да' : 'Нет'),
                    ],
                  ),
                  if (model.projection case final projection?)
                    LayerDetailsSection(
                      title: 'Проекция',
                      fields: [
                        LayerDetailsFieldRow(label: 'Имя', value: projection.name),
                        LayerDetailsFieldRow(label: 'Id', value: projection.id),
                        LayerDetailsFieldRow(label: 'Геоид', value: projection.geoid),
                        LayerDetailsFieldRow(label: 'Масштабы', value: projection.zooms),
                        if (projection.coverage case final coverage?)
                          LayerDetailsFieldRow(label: 'Покрытие', value: coverage),
                      ],
                    ),
                  if (model.files case final files?)
                    LayerDetailsSection(
                      title: 'Файлы',
                      fields: [
                        if (files.folder case final folder?) LayerDetailsFieldRow(label: 'Папка', value: folder),
                        for (final file in files.files) LayerDetailsFieldRow(label: 'Файл', value: file),
                        LayerDetailsFieldRow(label: 'Размер', value: files.size),
                        if (files.version case final version?) LayerDetailsFieldRow(label: 'Версия', value: version),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}
