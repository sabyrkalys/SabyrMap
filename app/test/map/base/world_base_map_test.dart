import 'dart:io';

import 'package:app/map/base/world_base_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.bytes);

  Uint8List bytes;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    expect(key, WorldBaseMap.asset);
    return ByteData.sublistView(bytes);
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('world'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('copies the map out of the APK once; a different size (new APK) is copied again', () async {
    final bundle = _Bundle(Uint8List.fromList([1, 2, 3]));
    final world = WorldBaseMap(bundle: bundle, directory: () async => Directory('${dir.path}/base'));

    final path = await world.install();
    expect(path, '${dir.path}/base/world.mbtiles');
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    final modified = File(path).lastModifiedSync();

    await world.install();
    expect(File(path).lastModifiedSync(), modified);

    bundle.bytes = Uint8List.fromList([4, 5, 6, 7]);
    await world.install();
    expect(File(path).readAsBytesSync(), [4, 5, 6, 7]);
  });

  test('the bundled file is a real MBTiles', () async {
    final file = File('assets/base/world.mbtiles');
    expect(file.existsSync(), isTrue);
    expect(String.fromCharCodes(file.readAsBytesSync().take(15)), 'SQLite format 3');
  });
}
