import 'dart:convert';
import 'dart:io';

import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:app/maps/overlays/image_overlay_installer.dart';
import 'package:app/maps/overlays/kml_overlay_parser.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <GroundOverlay><name>Old map</name><drawOrder>2</drawOrder>
    <Icon><href>files/scan.jpg</href></Icon>
    <LatLonBox><north>51</north><south>50</south><east>31</east><west>30</west><rotation>3.5</rotation></LatLonBox>
  </GroundOverlay>
  <GroundOverlay><name>Online</name><Icon><href>https://x.example/a.png</href></Icon>
    <LatLonBox><north>1</north><south>0</south><east>1</east><west>0</west></LatLonBox></GroundOverlay>
</Document></kml>''';

void main() {
  late Directory root;
  late KmlOverlayParser parser;
  setUp(() {
    root = Directory.systemTemp.createTempSync('overlay_');
    parser = KmlOverlayParser(tempRoot: root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a KML GroundOverlay gives one descriptor; online images are skipped', () async {
    Directory(p.join(root.path, 'files')).createSync();
    File(p.join(root.path, 'files', 'scan.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(root.path, 'doc.kml')).writeAsStringSync(kml);
    final overlays = await parser.parse(p.join(root.path, 'doc.kml'));
    final o = overlays.single;
    expect(o.name, 'Old map');
    expect(o.imagePath, p.join(root.path, 'files', 'scan.jpg'));
    expect(o.bounds, const MapBounds(northLat: 51, southLat: 50, westLon: 30, eastLon: 31));
    expect(o.rotation, 3.5);
    expect(o.drawOrder, 2);
  });

  test('KMZ is unpacked and image paths resolved', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('doc.kml', utf8.encode(kml)))
      ..addFile(ArchiveFile.bytes('files/scan.jpg', [9, 8, 7]));
    final kmz = File(p.join(root.path, 'map.kmz'))..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    final o = (await parser.parse(kmz.path)).single;
    expect(File(o.imagePath).readAsBytesSync(), [9, 8, 7]);
    expect(p.isWithin(root.path, o.imagePath), isTrue);
  });

  test('broken KML, KMZ without kml, missing file → FormatException', () async {
    File(p.join(root.path, 'bad.kml')).writeAsStringSync('<kml><GroundOverlay>');
    await expectLater(parser.parse(p.join(root.path, 'bad.kml')), throwsFormatException);
    final empty = File(p.join(root.path, 'e.kmz'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('a.txt', [1]))));
    await expectLater(parser.parse(empty.path), throwsFormatException);
    await expectLater(parser.parse(p.join(root.path, 'none.kml')), throwsFormatException);
  });

  test('the installer copies the image with a .bounds file the scanner reads', () async {
    Directory(p.join(root.path, 'files')).createSync();
    File(p.join(root.path, 'files', 'scan.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(root.path, 'doc.kml')).writeAsStringSync(kml);
    final overlay = (await parser.parse(p.join(root.path, 'doc.kml'))).single;
    final paths = StoragePaths.forRoot(p.join(root.path, 'app'));
    final installed = await ImageOverlayInstaller(paths, StorageService(paths)).install(overlay);
    expect(p.dirname(installed.path), paths.maps);
    expect(p.basename(installed.path), 'old_map.jpg');
    expect(installed.bounds, overlay.bounds);
    final scanned = await FileMapScanner(paths).readMetadata(installed.path);
    expect(scanned!.bounds, overlay.bounds);
    expect(scanned.displayName, 'Old map');
  });
}
