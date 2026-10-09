import 'dart:io';

import 'package:app/maps/on_demand/aqx_descriptor.dart';
import 'package:app/maps/on_demand/aqx_parser.dart';
import 'package:app/maps/on_demand/aqx_registry.dart';
import 'package:app/maps/on_demand/aqx_store.dart';
import 'package:app/maps/on_demand/zoom_range.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';

const String full = r'''<?xml version="1.0"?>
<aqx version="2">
  <name>Topo</name>
  <description>Topographic</description>
  <source id="topo">
    <zoom-levels>1-17</zoom-levels>
    <server>https://a.example/{$z}/{$x}/{$y}.png</server>
    <server url="https://b.example/{$z}/{$x}/{$y}.png">
      <header name="User-Agent">sabyrmap</header>
    </server>
    <update-delay>30d</update-delay>
    <max-threads>9</max-threads>
    <projection-code>EPSG:3857</projection-code>
    <tile-size>512</tile-size>
    <clear-color min="250,250,250" max="255,255,255"/>
    <variable name="layer" default="topo"/>
    <param name="key">abc</param>
    <future-thing>ignored</future-thing>
    <insecure>true</insecure>
  </source>
</aqx>''';

void main() {
  const parser = AqxParser();

  test('a minimal AQX', () {
    final d = parser.parseString(r'<aqx><name>Plain</name><server>https://x/{$z}/{$x}/{$y}</server></aqx>');
    expect(d.id, 'plain');
    expect(d.name, 'Plain');
    expect(d.urlTemplate.template, r'https://x/{$z}/{$x}/{$y}');
    expect(d.zoomRange, const ZoomRange(0, 18));
    expect(d.maxThreads, 1);
    expect(d.projection.code, 'EPSG:3857');
    expect(d.version, 1);
    expect(d.servers, hasLength(1));
  });

  test('every field, zoom levels, several servers, unknown elements ignored', () {
    final d = parser.parseString(full);
    expect(d.id, 'topo');
    expect(d.description, 'Topographic');
    expect(d.version, 2);
    expect(d.zoomRange, const ZoomRange(1, 17));
    expect(d.servers.map((s) => s.url), [r'https://a.example/{$z}/{$x}/{$y}.png', r'https://b.example/{$z}/{$x}/{$y}.png']);
    expect(d.servers.last.headers, {'User-Agent': 'sabyrmap'});
    expect(d.updateDelay, const Duration(days: 30));
    expect(d.maxThreads, 3);
    expect(d.projection.tileSize, 512);
    expect((d.clearColorMinR, d.clearColorMaxB), (250, 255));
    expect(d.defaultParams, {'layer': 'topo', 'key': 'abc'});
    expect(d.insecure, isTrue);
  });

  test('zoom levels as attributes', () {
    final d = parser.parseString(r'<aqx><name>A</name><zoom-levels min="3" max="12"/><server>u</server></aqx>');
    expect(d.zoomRange, const ZoomRange(3, 12));
  });

  test('broken XML, wrong root or missing parts are FormatException', () {
    for (final bad in [
      '<aqx><name>',
      '<map/>',
      '<aqx><server>u</server></aqx>',
      '<aqx><name>A</name></aqx>',
      '<aqx><name>A</name><server>u</server><zoom-levels>9-2</zoom-levels></aqx>',
      '<aqx><name>A</name><server>u</server><clear-color min="1,2"/></aqx>',
    ]) {
      expect(() => parser.parseString(bad), throwsFormatException, reason: bad);
    }
  });

  test('JSON round-trip and the store', () async {
    final d = parser.parseString(full);
    expect(AqxDescriptor.fromJson(d.toJson()), d);
    final store = AqxStore(await freshSettings());
    await store.save(d);
    expect(await store.byId('topo'), d);
    await store.remove('topo');
    expect(await store.loadAll(), isEmpty);
  });

  test('the registry reads *.aqx from datastore/maps and keeps errors', () async {
    final root = Directory.systemTemp.createTempSync('aqx_');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = StoragePaths.forRoot(root.path);
    Directory(paths.datastoreMaps).createSync(recursive: true);
    File(p.join(paths.datastoreMaps, 'topo.aqx')).writeAsStringSync(full);
    File(p.join(paths.datastoreMaps, 'plain.AQX')).writeAsStringSync(r'<aqx><name>P</name><server>u</server></aqx>');
    File(p.join(paths.datastoreMaps, 'bad.aqx')).writeAsStringSync('<aqx>');
    final registry = AqxRegistry(paths);
    await registry.refresh();
    expect(registry.all.map((d) => d.id), unorderedEquals(['topo', 'plain']));
    expect(registry.byId('topo')!.name, 'Topo');
    expect(registry.errors.single, startsWith('bad.aqx'));
  });
}
