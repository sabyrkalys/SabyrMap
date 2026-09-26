import 'dart:async';
import 'dart:convert';

import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const satellite = MapSource(
    id: 'google-satellite',
    name: 'Google Satellite',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    extraParams: {'mapType': 'satellite'},
  );
  const hybrid = MapSource(
    id: 'google-hybrid',
    name: 'Google Hybrid',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    extraParams: {'mapType': 'satellite', 'layerTypes': 'layerRoadmap'},
  );

  final start = DateTime.utc(2026, 9, 26, 12);
  int twoWeeksLater(DateTime from) => from.add(const Duration(days: 14)).millisecondsSinceEpoch ~/ 1000;

  late List<http.Request> requests;
  late DateTime now;

  GoogleTilesService service({String apiKey = 'KEY', http.Response Function(http.Request)? respond}) {
    requests = [];
    return GoogleTilesService(
      apiKey: apiKey,
      clock: () => now,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (respond != null) return respond(request);
        return http.Response(
          jsonEncode({'session': 'S${requests.length}', 'expiry': '${twoWeeksLater(now)}', 'tileWidth': 256}),
          200,
        );
      }),
    );
  }

  setUp(() => now = start);

  test('createSession posts mapType, language, region and layer types', () async {
    final s = service();
    final session = await s.sessionFor(hybrid);

    expect(session, 'S1');
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://tile.googleapis.com/v1/createSession?key=KEY');
    expect(request.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {
      'mapType': 'satellite',
      'language': 'ru-RU',
      'region': 'RU',
      'layerTypes': ['layerRoadmap'],
    });
  });

  test('one session per map type, reused for the app lifetime', () async {
    final s = service();
    expect(await s.sessionFor(satellite), 'S1');
    expect(await s.sessionFor(satellite), 'S1');
    expect(await s.sessionFor(hybrid), 'S2', reason: 'a session is tied to its map type');
    expect(requests, hasLength(2));
  });

  test('concurrent callers share one in-flight request', () async {
    final s = service();
    final both = await Future.wait([s.sessionFor(satellite), s.sessionFor(satellite)]);
    expect(both, ['S1', 'S1']);
    expect(requests, hasLength(1));
  });

  test('a session is renewed a day before it expires', () async {
    final s = service();
    await s.sessionFor(satellite);
    now = start.add(const Duration(days: 12, hours: 23));
    expect(await s.sessionFor(satellite), 'S1');
    now = start.add(const Duration(days: 13, minutes: 1));
    expect(await s.sessionFor(satellite), 'S2');
  });

  test('invalidate (e.g. after 401/403) forces a new session', () async {
    final s = service();
    await s.sessionFor(satellite);
    s.invalidate(satellite);
    expect(await s.sessionFor(satellite), 'S2');
  });

  test('tileUrlTemplate uses the session and key', () async {
    final s = service();
    expect(
      await s.tileUrlTemplate(satellite),
      'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=S1&key=KEY',
    );
  });

  test('HTTP errors become GoogleTilesException with a user message', () async {
    final s = service(respond: (_) => http.Response('{"error":{"message":"API key not valid"}}', 403));
    await expectLater(
      s.sessionFor(satellite),
      throwsA(isA<GoogleTilesException>().having((e) => e.message, 'message', 'Google-слой недоступен, проверьте подключение')),
    );
  });

  test('network failures become GoogleTilesException and do not poison the cache', () async {
    var fail = true;
    requests = [];
    final s = GoogleTilesService(
      apiKey: 'KEY',
      clock: () => now,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (fail) throw http.ClientException('offline');
        return http.Response(jsonEncode({'session': 'OK', 'expiry': '${twoWeeksLater(now)}'}), 200);
      }),
    );
    await expectLater(s.sessionFor(satellite), throwsA(isA<GoogleTilesException>()));
    fail = false;
    expect(await s.sessionFor(satellite), 'OK');
  });

  test('a malformed response is an error, not a crash', () async {
    final s = service(respond: (_) => http.Response('{"nope":1}', 200));
    await expectLater(s.sessionFor(satellite), throwsA(isA<GoogleTilesException>()));
  });

  test('no API key → clear error without any request', () async {
    final s = service(apiKey: '');
    await expectLater(
      s.sessionFor(satellite),
      throwsA(isA<GoogleTilesException>().having((e) => e.message, 'message', contains('ключ'))),
    );
    expect(requests, isEmpty);
  });

  test('a source without a mapType is rejected', () async {
    final s = service();
    const bad = MapSource(id: 'x', name: 'x', format: TileFormat.raster, storageMode: StorageMode.onlineOnly);
    expect(() => s.sessionFor(bad), throwsA(isA<ArgumentError>()));
  });

  test('timeouts surface as errors', () async {
    final never = Completer<http.Response>();
    final s = GoogleTilesService(
      apiKey: 'KEY',
      clock: () => now,
      timeout: const Duration(milliseconds: 10),
      httpClient: MockClient((_) => never.future),
    );
    await expectLater(s.sessionFor(satellite), throwsA(isA<GoogleTilesException>()));
  });

  group('verifyAccess', () {
    GoogleTilesService probing(List<int> tileStatuses) {
      requests = [];
      var tileCall = 0;
      var sessionCall = 0;
      return GoogleTilesService(
        apiKey: 'KEY',
        clock: () => now,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('createSession')) {
            sessionCall++;
            return http.Response(jsonEncode({'session': 'S$sessionCall', 'expiry': '${twoWeeksLater(now)}'}), 200);
          }
          final status = tileStatuses[tileCall++ < tileStatuses.length ? tileCall - 1 : tileStatuses.length - 1];
          return http.Response.bytes(const [1], status);
        }),
      );
    }

    test('fetches the zoom-0 tile with the session once and remembers success', () async {
      final s = probing([200]);
      await s.verifyAccess(satellite);
      await s.verifyAccess(satellite);
      final tiles = requests.where((r) => r.url.path.contains('2dtiles')).toList();
      expect(tiles, hasLength(1));
      expect(tiles.single.url.path, '/v1/2dtiles/0/0/0');
      expect(tiles.single.url.queryParameters, {'session': 'S1', 'key': 'KEY'});
    });

    test('401/403 → a new session is tried once before giving up', () async {
      final ok = probing([403, 200]);
      await ok.verifyAccess(satellite);
      expect(requests.where((r) => r.url.path.endsWith('createSession')), hasLength(2));

      final bad = probing([403, 403]);
      await expectLater(
        bad.verifyAccess(satellite),
        throwsA(isA<GoogleTilesException>().having((e) => e.message, 'message', GoogleTilesService.userMessage)),
      );
    });
  });
}

