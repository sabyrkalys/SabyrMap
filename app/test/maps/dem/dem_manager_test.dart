import 'dart:io';
import 'dart:typed_data';

import 'package:app/maps/dem/dem_descriptor.dart';
import 'package:app/maps/dem/dem_manager.dart';
import 'package:app/maps/dem/dem_settings.dart';
import 'package:app/maps/dem/dem_tile.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';

void main() {
  late Directory root;
  late StoragePaths paths;
  late DemManager dem;

  /// 3×3 сетка: строки с севера на юг.
  Uint8List grid(List<int> values) {
    final data = ByteData(values.length * 2);
    for (final (i, v) in values.indexed) {
      data.setInt16(i * 2, v);
    }
    return data.buffer.asUint8List();
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dem_');
    paths = StoragePaths.forRoot(root.path);
    final sub = Directory(p.join(paths.datastoreDem, 'eu'))..createSync(recursive: true);
    // Север: 200 200 200; середина: 100 100 100; юг: 0 0 0.
    File(p.join(sub.path, 'N50E030.hgt')).writeAsBytesSync(grid([200, 200, 200, 100, 100, 100, 0, 0, 0]));
    File(p.join(paths.datastoreDem, 'S01W001.hgt')).writeAsBytesSync(grid([-10, -32768, 5, 1, 1, 1, 1, 1, 1]));
    File(p.join(paths.datastoreDem, 'readme.txt')).writeAsStringSync('x');
    File(p.join(paths.datastoreDem, 'N10E010.hgt')).writeAsBytesSync([1, 2, 3]);
    dem = DemManager(paths, const DemSettings());
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('scanFolder finds .hgt files in subfolders', () async {
    final found = await dem.scanFolder(paths.datastoreDem);
    expect(found.map((d) => (d.tileX, d.tileY)), unorderedEquals([(30, 50), (-1, -1)]));
    expect(found.every((d) => d.samplesPerRow == 3 && d.isCustom), isTrue);
  });

  test('loadTile reads big-endian rows', () async {
    final d = (await dem.findTileFor(loc(50.5, 30.5)))!;
    final tile = (await dem.loadTile(d))!;
    expect(tile.elevations.sublist(0, 4), [200, 200, 200, 100]);
    expect(await dem.loadTile(const DemDescriptor(path: '/none.hgt', tileX: 0, tileY: 0, samplesPerRow: 3)), isNull);
  });

  test('elevationAt interpolates bilinearly', () async {
    expect(await dem.elevationAt(loc(50.5, 30.5)), closeTo(100, 1e-9));
    expect(await dem.elevationAt(loc(50.75, 30.1)), closeTo(150, 1e-9));
    expect(await dem.elevationAt(loc(50.9999999, 30.9999999)), closeTo(200, 1e-4));
    expect(await dem.elevationAt(loc(51, 31)), isNull);
    expect(await dem.elevationAt(loc(50, 30)), closeTo(0, 1e-9));
  });

  test('negative heights; void points and missing tiles give null', () async {
    expect(await dem.elevationAt(loc(-0.0001, -0.9999)), closeTo(-10, 0.01));
    expect(await dem.elevationAt(loc(-0.0001, -0.5)), closeTo(1, 0.01));
    expect(await dem.elevationAt(loc(10.5, 10.5)), isNull);
    expect(await dem.elevationAt(loc(0.5, 0.5)), isNull);
  });

  test('disabled elevation data gives null; settings round-trip', () async {
    final maps = await freshMapsSettings();
    final managed = DemManager(paths, const DemSettings(), store: maps);
    await managed.saveSettings(const DemSettings(useElevationData: false, autoDownload: true));
    expect(await managed.elevationAt(loc(50.5, 30.5)), isNull);
    final reloaded = DemManager(paths, const DemSettings(), store: maps);
    expect(await reloaded.loadSettings(), const DemSettings(useElevationData: false, autoDownload: true));
  });

  test('a tile sample outside 0..1 is null', () {
    final tile = DemTile(
      descriptor: const DemDescriptor(path: '', tileX: 0, tileY: 0, samplesPerRow: 2),
      elevations: Uint16List.fromList([1, 2, 3, 4]),
    );
    expect(tile.sample(1.2, 0.5), isNull);
    expect(tile.sample(0, 1), 1);
    expect(tile.sample(1, 0), 4);
  });

  test('void samples are skipped; all void is null', () {
    DemTile tileOf(List<int> v) => DemTile(
      descriptor: const DemDescriptor(path: '', tileX: 0, tileY: 0, samplesPerRow: 2),
      elevations: Uint16List.fromList(v),
    );
    expect(tileOf([DemTile.voidValue, 10, 10, 10]).sample(0.5, 0.5), 10);
    expect(tileOf(List.filled(4, DemTile.voidValue)).sample(0.5, 0.5), isNull);
  });
}
