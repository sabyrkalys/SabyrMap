import 'dart:convert';

import 'package:app/map/regions/regions_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

void main() {
  final bounds = LatLngBounds(southwest: const LatLng(48.14, 24.47), northeast: const LatLng(48.18, 24.53));

  RegionsApi api(Future<http.Response> Function(http.Request) handler) =>
      RegionsApi(baseUrl: 'http://api.test', httpClient: MockClient(handler));

  test('estimate sends the bbox as west, south, east, north', () async {
    late Map<String, dynamic> sent;
    final estimate = await api((request) async {
      expect(request.url.toString(), 'http://api.test/regions/estimate');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'parts': [], 'style_bytes': 1, 'total_bytes': 2048, 'max_bytes': 4096, 'allowed': true}), 200);
    }).estimate(mapId: 'server-hybrid-day', bounds: bounds, maxZoom: 16);

    expect(sent, {'map_id': 'server-hybrid-day', 'bbox': [24.47, 48.14, 24.53, 48.18], 'max_zoom': 16});
    expect(estimate.totalBytes, 2048);
    expect(estimate.allowed, isTrue);
  });

  test('a job is read with its files', () async {
    final job = await api((_) async => http.Response(
          jsonEncode({
            'id': 'j1', 'map_id': 'm', 'status': 'ready', 'progress': 1.0, 'error': null,
            'files': [{'name': 'osm.mbtiles', 'size': 10, 'sha256': 'ab'}],
          }),
          200,
        )).get('j1');

    expect(job.status, RegionJobStatus.ready);
    expect(job.files.single.name, 'osm.mbtiles');
  });

  test('the server explanation becomes the message', () async {
    final limited = api((_) async => http.Response.bytes(utf8.encode(jsonEncode({'detail': 'Не больше 5 регионов в час'})), 429));
    await expectLater(
      limited.create(mapId: 'm', bbox: [1, 2, 3, 4], maxZoom: 10),
      throwsA(isA<RegionException>().having((e) => e.message, 'message', 'Не больше 5 регионов в час')),
    );
    final down = api((_) async => throw http.ClientException('offline'));
    await expectLater(down.get('x'), throwsA(isA<RegionException>().having((e) => e.message, 'message', 'Нет связи с сервером карт')));
  });

  test('download URLs escape the file name', () {
    expect(api((_) async => http.Response('', 200)).downloadUri('j1', 'style.zip').toString(),
        'http://api.test/regions/j1/download/style.zip');
  });
}
