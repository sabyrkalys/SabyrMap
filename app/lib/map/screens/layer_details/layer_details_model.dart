import 'package:path/path.dart' as p;

import '../../../format_bytes.dart';
import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';
import '../available_maps/available_maps_models.dart';

/// Что показывает экран «Детали слоя».
class LayerDetailsModel {
  const LayerDetailsModel({
    required this.displayName,
    required this.groupTitle,
    this.previewSource,
    required this.info,
    this.projection,
    this.files,
  });

  final String displayName;

  /// Группа карты: «Сервер карт», «Установленные карты», «Ортофотопланы»…
  final String groupTitle;

  /// Чья картинка в превью; null — плейсхолдер.
  final MapSource? previewSource;
  final LayerInfoSection info;
  final LayerProjectionSection? projection;
  final LayerFilesSection? files;
}

class LayerInfoSection {
  const LayerInfoSection({required this.name, required this.type, required this.canBeAddedAsLayer});

  final String name;

  /// «Спутник · Растр · Онлайн»
  final String type;
  final bool canBeAddedAsLayer;
}

class LayerProjectionSection {
  const LayerProjectionSection({
    required this.name,
    required this.id,
    required this.geoid,
    required this.zooms,
    this.coverage,
  });

  /// Все карты приложения рисуются в одной проекции.
  static const LayerProjectionSection webMercator = LayerProjectionSection(
    name: 'EPSG:3857 (Web Mercator)',
    id: 'EPSG:3857',
    geoid: 'Сфера WGS 84 (R = 6 378 137 м)',
    zooms: '',
  );

  final String name;
  final String id;
  final String geoid;

  /// «0–17»
  final String zooms;

  /// Границы скачанного участка, если известны.
  final String? coverage;
}

class LayerFilesSection {
  const LayerFilesSection({this.folder, this.files = const [], required this.size, this.version});

  final String? folder;
  final List<String> files;

  /// «57.5 МБ», для онлайн-карты — «≈ 3.0 МБ в кэше».
  final String size;

  /// Версия данных сервера или дата скачивания.
  final String? version;
}

/// Тип карты по-русски.
String mapKindLabel(MapKind kind) => switch (kind) {
  MapKind.scheme => 'Схема',
  MapKind.terrain => 'Рельеф',
  MapKind.hybrid => 'Гибрид',
  MapKind.satellite => 'Спутник',
};

/// Собирает [LayerDetailsModel] из каталога и того, что лежит на телефоне.
abstract final class LayerDetailsModelBuilder {
  /// Одна карта [source] из группы [provider]. [local] — её файл или
  /// папка (установленные карты, ортофотопланы); [cachedBytes] — кэш
  /// тайлов онлайн-карты.
  static LayerDetailsModel fromSource({
    required MapSource source,
    required MapProvider provider,
    LocalMapInfo? local,
    int cachedBytes = 0,
    String? groupTitle,
  }) {
    final isOrthophoto = provider.id == CatalogRepository.orthophotoProviderId;
    final isFile = source.storageMode == StorageMode.offlineRegion;
    final kind = isOrthophoto ? 'Ортофотоплан' : mapKindLabel(mapKindOf(source));
    final bbox = local?.bbox;
    String coord(double v) => v.toStringAsFixed(3);
    return LayerDetailsModel(
      displayName: source.name,
      groupTitle: groupTitle ?? provider.name,
      previewSource: source,
      info: LayerInfoSection(
        name: source.name,
        type: [kind, source.format == TileFormat.raster ? 'Растр' : 'Вектор', isFile ? 'Файл' : 'Онлайн'].join(' · '),
        canBeAddedAsLayer:
            source.canBeOverlay && source.format == TileFormat.raster && !provider.isolated && !isOrthophoto,
      ),
      projection: LayerProjectionSection(
        name: LayerProjectionSection.webMercator.name,
        id: LayerProjectionSection.webMercator.id,
        geoid: LayerProjectionSection.webMercator.geoid,
        zooms: '${source.minZoom}–${local?.maxZoom ?? source.maxZoom}',
        coverage: bbox == null
            ? null
            : '${coord(bbox[1])}…${coord(bbox[3])} с. ш., ${coord(bbox[0])}…${coord(bbox[2])} в. д.',
      ),
      files: _files(source, local, cachedBytes),
    );
  }

  static LayerFilesSection? _files(MapSource source, LocalMapInfo? local, int cachedBytes) {
    final created = local?.createdAt?.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final version = created != null ? '${two(created.day)}.${two(created.month)}.${created.year}' : source.version;
    if (local != null) {
      final path = local.path;
      final isFolder = local.files.length != 1 || p.basename(path ?? '') != local.files.single;
      return LayerFilesSection(
        folder: path == null ? null : (isFolder ? path : p.dirname(path)),
        files: local.files,
        size: formatBytes(local.sizeBytes),
        version: version,
      );
    }
    if (cachedBytes > 0) return LayerFilesSection(size: '≈ ${formatBytes(cachedBytes)} в кэше', version: version);
    return null;
  }

  /// Встроенная карта мира под всеми картами («Базовая карта»).
  static LayerDetailsModel world({String? path, int sizeBytes = 0}) => LayerDetailsModel(
    displayName: 'Базовая карта',
    groupTitle: 'Встроена в приложение',
    info: const LayerInfoSection(
      name: 'Базовая карта (Natural Earth)',
      type: 'Спутник · Растр · Файл',
      canBeAddedAsLayer: false,
    ),
    projection: LayerProjectionSection(
      name: LayerProjectionSection.webMercator.name,
      id: LayerProjectionSection.webMercator.id,
      geoid: LayerProjectionSection.webMercator.geoid,
      zooms: '0–5',
    ),
    files: path == null
        ? null
        : LayerFilesSection(folder: p.dirname(path), files: [p.basename(path)], size: formatBytes(sizeBytes)),
  );

  /// Все ортофотопланы вместе (строка «Ортофотопланы» в «Картах на экране»).
  static LayerDetailsModel orthophotos({required List<MapSource> sources, required Map<String, LocalMapInfo> local}) {
    final infos = [for (final s in sources) local[s.id]];
    final paths = [for (final i in infos) i?.path].whereType<String>().toList();
    final size = infos.fold<int>(0, (sum, i) => sum + (i?.sizeBytes ?? 0));
    return LayerDetailsModel(
      displayName: 'Ортофотопланы',
      groupTitle: 'Ортофотопланы',
      previewSource: sources.firstOrNull,
      info: const LayerInfoSection(
        name: 'Ортофотопланы',
        type: 'Ортофотоплан · Растр · Файл',
        canBeAddedAsLayer: false,
      ),
      projection: LayerProjectionSection(
        name: LayerProjectionSection.webMercator.name,
        id: LayerProjectionSection.webMercator.id,
        geoid: LayerProjectionSection.webMercator.geoid,
        zooms: sources.isEmpty
            ? '—'
            : '${sources.map((s) => s.minZoom).reduce((a, b) => a < b ? a : b)}–'
                  '${sources.map((s) => s.maxZoom).reduce((a, b) => a > b ? a : b)}',
      ),
      files: sources.isEmpty
          ? null
          : LayerFilesSection(
              folder: paths.isEmpty ? null : p.dirname(paths.first),
              files: [for (final i in infos) ...?i?.files],
              size: formatBytes(size),
            ),
    );
  }
}
