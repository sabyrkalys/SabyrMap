import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/screens/layer_details/layer_details_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const satellite = MapSource(
    id: 'server-satellite',
    name: 'Спутник',
    tileUrlTemplate: 'https://t/satellite/{z}/{x}/{y}',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineCache,
    maxZoom: 17,
    canBeOverlay: true,
    version: 'v1',
  );
  const server = MapProvider(id: 'server', name: 'Сервер карт', sources: [satellite]);
  const karpaty = MapSource(
    id: 'local-Карпаты.mbtiles',
    name: 'Карпаты',
    tileUrlTemplate: 'mbtiles:///maps/Карпаты.mbtiles',
    format: TileFormat.raster,
    storageMode: StorageMode.offlineRegion,
    canBeOverlay: true,
  );
  const installed = MapProvider(id: 'local', name: 'Установленные карты', sources: [karpaty]);
  const googleSat = MapSource(
    id: 'google-satellite',
    name: 'Google Satellite',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
  );
  const google = MapProvider(id: 'google', name: 'Google Maps', isolated: true, sources: [googleSat]);
  const dobro = MapSource(
    id: 'ortho-Доброполье.mbtiles',
    name: 'Доброполье',
    tileUrlTemplate: 'mbtiles:///o/Доброполье.mbtiles',
    format: TileFormat.raster,
    storageMode: StorageMode.offlineRegion,
    minZoom: 10,
    maxZoom: 20,
    canBeOverlay: true,
  );
  const ortho = MapProvider(id: CatalogRepository.orthophotoProviderId, name: 'Ортофотопланы', sources: [dobro]);

  test('online map: info, Web Mercator projection, files only when something is cached', () {
    final model = LayerDetailsModelBuilder.fromSource(source: satellite, provider: server);
    expect(model.displayName, 'Спутник');
    expect(model.groupTitle, 'Сервер карт');
    expect(model.info.name, 'Спутник');
    expect(model.info.type, 'Спутник · Растр · Онлайн');
    expect(model.info.canBeAddedAsLayer, isTrue);
    expect(model.projection!.name, 'EPSG:3857 (Web Mercator)');
    expect(model.projection!.id, 'EPSG:3857');
    expect(model.projection!.geoid, isNotEmpty);
    expect(model.projection!.zooms, '0–17');
    expect(model.projection!.coverage, isNull);
    expect(model.files, isNull);

    final cached = LayerDetailsModelBuilder.fromSource(source: satellite, provider: server, cachedBytes: 3 * 1024 * 1024);
    expect(cached.files!.folder, isNull);
    expect(cached.files!.files, isEmpty);
    expect(cached.files!.size, '≈ 3.0 МБ в кэше');
    expect(cached.files!.version, 'v1');
  });

  test('file map: its folder, the one file, size; a region also has coverage and date', () {
    final file = LayerDetailsModelBuilder.fromSource(
      source: karpaty,
      provider: installed,
      local: const LocalMapInfo(sizeBytes: 5 * 1024 * 1024, path: '/maps/Карпаты.mbtiles', files: ['Карпаты.mbtiles']),
    );
    expect(file.info.type, 'Схема · Растр · Файл');
    expect(file.files!.folder, '/maps');
    expect(file.files!.files, ['Карпаты.mbtiles']);
    expect(file.files!.size, '5.0 МБ');
    expect(file.files!.version, isNull);

    final region = LayerDetailsModelBuilder.fromSource(
      source: karpaty,
      provider: installed,
      groupTitle: 'OPENSTREETMAP',
      local: LocalMapInfo(
        sizeBytes: 1024,
        path: '/maps/Говерла',
        files: const ['manifest.json', 'osm.mbtiles'],
        createdAt: DateTime(2026, 10, 7, 12),
        bbox: const [24.4, 48.1, 24.6, 48.2],
        maxZoom: 15,
      ),
    );
    expect(region.groupTitle, 'OPENSTREETMAP');
    expect(region.files!.folder, '/maps/Говерла');
    expect(region.files!.files, ['manifest.json', 'osm.mbtiles']);
    expect(region.files!.version, '07.10.2026');
    expect(region.projection!.zooms, '0–15');
    expect(region.projection!.coverage, '48.100…48.200 с. ш., 24.400…24.600 в. д.');
  });

  test('isolated and orthophoto maps cannot be added as a layer', () {
    expect(LayerDetailsModelBuilder.fromSource(source: googleSat, provider: google).info.canBeAddedAsLayer, isFalse);
    final photo = LayerDetailsModelBuilder.fromSource(source: dobro, provider: ortho);
    expect(photo.info.canBeAddedAsLayer, isFalse);
    expect(photo.info.type, 'Ортофотоплан · Растр · Файл');
  });

  test('all orthophotos together: folder, every file, total size', () {
    final model = LayerDetailsModelBuilder.orthophotos(
      sources: [dobro],
      local: const {
        'ortho-Доброполье.mbtiles': LocalMapInfo(sizeBytes: 2048, path: '/o/Доброполье.mbtiles', files: ['Доброполье.mbtiles']),
      },
    );
    expect(model.displayName, 'Ортофотопланы');
    expect(model.info.canBeAddedAsLayer, isFalse);
    expect(model.projection!.zooms, '10–20');
    expect(model.files!.folder, '/o');
    expect(model.files!.files, ['Доброполье.mbtiles']);
    expect(model.files!.size, '2 КБ');
    expect(LayerDetailsModelBuilder.orthophotos(sources: const [], local: const {}).files, isNull);
  });
}
