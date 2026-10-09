import 'dart:io';
import 'dart:typed_data';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../explorer_fixture.dart';

void main() {
  late ExplorerFixture f;
  setUp(() async => f = await ExplorerFixture.create());
  tearDown(() => f.dispose());

  test('a waypoint gives name, colour, icon, coordinates and times', () async {
    final path = await f.waypoint('Bunker', lat: 50.4501, lon: 30.5234, color: 0xFF00FF00, icon: 'flag');
    final item = (await f.reader.read(path))!;
    expect(item.path, path);
    expect(item.name, 'Bunker');
    expect(item.type, LandmarkType.waypoint);
    expect(item.colorValue, 0xFF00FF00);
    expect(item.iconId, 'flag');
    expect(item.latitude, closeTo(50.4501, 1e-7));
    expect(item.longitude, closeTo(30.5234, 1e-7));
    expect(item.createdAt, 1760000000000);
    expect(item.updatedAt, 1760000000000);
    expect(item.fileSizeBytes, File(path).lengthSync());
    expect(item.lengthMeters, isNull);
  });

  test('without a name or colour: name from the file, default colour', () async {
    final path = await f.repository.save(
      LandmarkFile.of(const WaypointObject(location: LandmarkLocation(longitude: 0, latitude: 0))),
    );
    final item = (await f.reader.read(path))!;
    expect(item.name, 'untitled_1760000000000');
    expect(item.colorValue, LandmarkItem.defaultColor);
  });

  test('composite files: no coordinates, statistics from metadata', () async {
    final path = await f.track('Walk', extra: {'length_m': 1234.5, 'duration_ms': 3600000, 'activity': 'hike', 'year': 2025});
    final item = (await f.reader.read(path))!;
    expect(item.type, LandmarkType.track);
    expect(item.latitude, isNull);
    expect(item.longitude, isNull);
    expect(item.lengthMeters, 1234.5);
    expect(item.durationMs, 3600000);
    expect(item.activity, 'hike');
    expect(item.year, 2025);

    for (final object in <LandmarkObject>[const SetObject(), const RouteObject(), const AreaObject()]) {
      final saved = await f.repository.save(LandmarkFile.of(object));
      final read = (await f.reader.read(saved))!;
      expect(read.type, object.type);
      expect(read.latitude, isNull);
    }
  });

  test('the payload is not parsed: a broken body after the metadata is fine', () async {
    final path = await f.track('Walk');
    final bytes = File(path).readAsBytesSync();
    // Ломаем последние байты (содержимое трека), заголовок и метаданные целы.
    bytes.fillRange(bytes.length - 8, bytes.length, 0xFF);
    File(path).writeAsBytesSync(bytes);
    expect((await f.reader.read(path))!.name, 'Walk');
  });

  test('long metadata beyond the first chunk is read', () async {
    final path = await f.waypoint('Big', extra: {'description': 'x' * 20000});
    final item = (await f.reader.read(path))!;
    expect(item.name, 'Big');
    expect(item.latitude, closeTo(50.45, 1e-7));
  });

  test('a foreign file is skipped', () async {
    final path = p.join(f.paths.landmarks, 'foreign.wpt');
    File(path).writeAsBytesSync(Uint8List.fromList(List.generate(64, (i) => i)));
    expect(await f.reader.read(path), isNull);
    File(path).writeAsBytesSync(const []);
    expect(await f.reader.read(path), isNull);
  });

  test('a truncated file is skipped', () async {
    final path = await f.waypoint('Bunker', extra: {'description': 'long text'});
    final bytes = File(path).readAsBytesSync();
    File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    expect(await f.reader.read(path), isNull);
    // У точки обрезана только координата.
    final full = LandmarkCodec.encode(await f.repository.load(await f.waypoint('X')));
    File(path).writeAsBytesSync(full.sublist(0, full.length - 9));
    expect(await f.reader.read(path), isNull);
  });

  test('a missing file is skipped', () async {
    expect(await f.reader.read(p.join(f.paths.landmarks, 'none.wpt')), isNull);
  });

  test('1000 waypoints are all read', () async {
    final dir = p.join(f.paths.landmarks, 'many');
    Directory(dir).createSync();
    final bytes = LandmarkCodec.encode(await f.repository.load(await f.waypoint('Template')));
    for (var i = 0; i < 1000; i++) {
      File(p.join(dir, 'p_${i.toString().padLeft(4, '0')}.wpt')).writeAsBytesSync(bytes);
    }
    final items = await f.reader.readAll(dir);
    expect(items, hasLength(1000));
    expect(items.first.path, p.join(dir, 'p_0000.wpt'));
    expect(items.every((i) => i.name == 'Template'), isTrue);
  });

  test('readAll skips links, foreign extensions and broken files', () async {
    final good = await f.waypoint('Good');
    Link(p.join(f.paths.landmarks, 'link.wpt')).createSync(good);
    File(p.join(f.paths.landmarks, 'notes.txt')).writeAsStringSync('x');
    File(p.join(f.paths.landmarks, 'broken.wpt')).writeAsBytesSync([1, 2, 3]);
    expect(await f.reader.read(p.join(f.paths.landmarks, 'link.wpt')), isNull);
    final items = await f.reader.readAll(f.paths.landmarks);
    expect(items.map((i) => i.path), [good]);
  });
}
