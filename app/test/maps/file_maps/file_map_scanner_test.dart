import 'dart:convert';
import 'dart:io';

import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late StoragePaths paths;
  late FileMapScanner scanner;
  setUp(() {
    root = Directory.systemTemp.createTempSync('maps_');
    paths = StoragePaths.forRoot(root.path);
    Directory(paths.maps).createSync(recursive: true);
    Directory(paths.datastoreMaps).createSync(recursive: true);
    scanner = FileMapScanner(paths);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File put(String dir, String name, [List<int> bytes = const [1, 2, 3]]) =>
      File(p.join(dir, name))..writeAsBytesSync(bytes);

  test('an empty or missing folder gives an empty list', () async {
    expect(await scanner.scanFolder(paths.maps), isEmpty);
    expect(await scanner.scanFolder(p.join(root.path, 'none')), isEmpty);
  });

  test('unsupported and non-raster files are ignored', () async {
    put(paths.maps, 'notes.txt');
    put(paths.maps, 'N50E030.hgt');
    put(paths.maps, 'topo.aqm.bounds');
    expect(await scanner.scanFolder(paths.maps), isEmpty);
  });

  test('a .pgd with a bounds file gives full metadata', () async {
    put(paths.maps, 'kyiv.pgd', List.filled(100, 7));
    File(p.join(paths.maps, 'kyiv.pgd.bounds')).writeAsStringSync(
      jsonEncode({'north': 50.6, 'south': 50.3, 'west': 30.2, 'east': 30.8, 'minZoom': 8, 'maxZoom': 16, 'name': 'Kyiv'}),
    );
    final maps = await scanner.scanFolder(paths.maps);
    final m = maps.single.metadata;
    expect(m.sourceFormatId, 'pgd');
    expect(m.displayName, 'Kyiv');
    expect(m.bounds, const MapBounds(northLat: 50.6, southLat: 50.3, westLon: 30.2, eastLon: 30.8));
    expect((m.minZoom, m.maxZoom), (8, 16));
    expect(m.fileSizeBytes, 100);
    expect(maps.single.displayPath, 'maps/kyiv.pgd');
  });

  test('a .pgd without a bounds file still has metadata, no bounds; images too', () async {
    put(paths.maps, 'area.pgd');
    put(paths.maps, 'scan.png');
    final maps = await scanner.scanFolder(paths.maps);
    expect(maps.map((d) => d.metadata.sourceFormatId), ['pgd', 'image']);
    expect(maps.every((d) => d.metadata.bounds == null), isTrue);
  });

  test('a ZIP of XYZ tiles gives zooms and bounds', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('tiles/1/1/0.png', [1]))
      ..addFile(ArchiveFile.bytes('tiles/2/2/1.png', [1]))
      ..addFile(ArchiveFile.bytes('tiles/2/3/1.png', [1]));
    put(paths.maps, 'tiles.zip', ZipEncoder().encodeBytes(archive));
    final m = (await scanner.readMetadata(p.join(paths.maps, 'tiles.zip')))!;
    expect(m.sourceFormatId, 'zip-xyz');
    expect((m.minZoom, m.maxZoom), (1, 2));
    expect(m.bounds!.westLon, 0);
    expect(m.bounds!.eastLon, 180);
    expect(m.bounds!.southLat, 0);
  });

  test('a KML overlay gives its LatLonBox', () async {
    File(p.join(paths.maps, 'scan.kml')).writeAsStringSync('''<kml xmlns="http://www.opengis.net/kml/2.2">
<GroundOverlay><name>Old map</name><Icon><href>scan.jpg</href></Icon>
<LatLonBox><north>51</north><south>50</south><east>31</east><west>30</west></LatLonBox></GroundOverlay></kml>''');
    final m = (await scanner.readMetadata(p.join(paths.maps, 'scan.kml')))!;
    expect(m.displayName, 'Old map');
    expect(m.bounds, const MapBounds(northLat: 51, southLat: 50, westLon: 30, eastLon: 31));
  });

  test('scanAll covers maps and datastore/maps', () async {
    put(paths.maps, 'a.mbtiles');
    put(paths.datastoreMaps, 'b.sqlitedb');
    final all = await scanner.scanAll();
    expect(all.map((d) => p.basename(d.metadata.path)), ['a.mbtiles', 'b.sqlitedb']);
    expect(scanner.known, hasLength(2));
  });
}
