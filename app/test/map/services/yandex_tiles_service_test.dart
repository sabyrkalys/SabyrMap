import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const satellite = MapSource(
    id: 'yandex-satellite',
    name: 'Яндекс Спутник',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    tileUrlTemplate:
        'https://tiles.api-maps.yandex.ru/v1/tiles/?x={x}&y={y}&z={z}&lang=ru_RU&l=sat&projection=web_mercator',
    extraParams: {'layer': 'sat'},
  );

  late List<Uri> requested;

  YandexTilesService service({String apiKey = 'K+1', http.Response Function(Uri)? respond}) {
    requested = [];
    return YandexTilesService(
      apiKey: apiKey,
      httpClient: MockClient((request) async {
        requested.add(request.url);
        if (respond != null) return respond(request.url);
        return http.Response.bytes(const [0x89, 0x50, 0x4e, 0x47], 200);
      }),
    );
  }

  test('tile template gets the key appended, encoded', () {
    expect(
      service().tileUrlTemplate(satellite),
      'https://tiles.api-maps.yandex.ru/v1/tiles/?x={x}&y={y}&z={z}&lang=ru_RU&l=sat&projection=web_mercator&apikey=K%2B1',
    );
  });

  test('no key → clear error, no request', () async {
    final s = service(apiKey: '');
    expect(
      () => s.tileUrlTemplate(satellite),
      throwsA(isA<YandexTilesException>().having((e) => e.message, 'message', contains('ключ'))),
    );
    await expectLater(s.verifyAccess(satellite), throwsA(isA<YandexTilesException>()));
    expect(requested, isEmpty);
  });

  test('a source without a tile template is rejected', () {
    const bad = MapSource(id: 'x', name: 'x', format: TileFormat.raster, storageMode: StorageMode.onlineOnly);
    expect(() => service().tileUrlTemplate(bad), throwsA(isA<ArgumentError>()));
  });

  test('verifyAccess fetches the zoom-0 tile once and remembers success', () async {
    final s = service();
    await s.verifyAccess(satellite);
    await s.verifyAccess(satellite);
    expect(requested, hasLength(1));
    expect(requested.single.queryParameters, containsPair('z', '0'));
    expect(requested.single.queryParameters, containsPair('x', '0'));
    expect(requested.single.queryParameters, containsPair('apikey', 'K+1'));
  });

  test('403 → «key not accepted» message', () async {
    final s = service(respond: (_) => http.Response('Forbidden', 403));
    await expectLater(
      s.verifyAccess(satellite),
      throwsA(isA<YandexTilesException>().having((e) => e.message, 'message', 'Яндекс-слой недоступен: ключ не принят')),
    );
  });

  test('network failure → «check the connection», and a later retry can succeed', () async {
    var fail = true;
    requested = [];
    final s = YandexTilesService(
      apiKey: 'K',
      httpClient: MockClient((request) async {
        requested.add(request.url);
        if (fail) throw http.ClientException('offline');
        return http.Response.bytes(const [1], 200);
      }),
    );
    await expectLater(
      s.verifyAccess(satellite),
      throwsA(isA<YandexTilesException>().having((e) => e.message, 'message', 'Яндекс-слой недоступен, проверьте подключение')),
    );
    fail = false;
    await s.verifyAccess(satellite);
    expect(requested, hasLength(2));
  });

  test('other HTTP errors → «check the connection»', () async {
    final s = service(respond: (_) => http.Response('', 503));
    await expectLater(
      s.verifyAccess(satellite),
      throwsA(isA<YandexTilesException>().having((e) => e.message, 'message', 'Яндекс-слой недоступен, проверьте подключение')),
    );
  });
}
