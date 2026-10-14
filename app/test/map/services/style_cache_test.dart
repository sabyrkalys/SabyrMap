import 'dart:io';

import 'package:app/map/services/style_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final url = Uri.parse('https://46.150.103.61/tiles/style/hybrid-day');

  setUp(() => dir = Directory.systemTemp.createTempSync('styles'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a style from the server is kept; without the server the kept one is used', () async {
    var online = true;
    final cache = StyleCache(
      directory: () async => dir,
      network: (u) async => online ? '{"version": 8, "layers": []}' : throw const SocketException('down'),
    );
    expect(await cache.fetch(url), '{"version": 8, "layers": []}');
    online = false;
    expect(await cache.fetch(url), '{"version": 8, "layers": []}');
  });

  test('never fetched and no server: the server error', () async {
    final cache = StyleCache(directory: () async => dir, network: (_) async => throw const SocketException('down'));
    await expectLater(cache.fetch(url), throwsA(isA<SocketException>()));
  });

  test('an error page is not kept over a good style', () async {
    var body = '{"version": 8}';
    final cache = StyleCache(directory: () async => dir, network: (_) async => body);
    await cache.fetch(url);
    body = '<html>502</html>';
    expect(await cache.fetch(url), '{"version": 8}');
  });
}
