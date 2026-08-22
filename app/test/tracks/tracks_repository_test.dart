import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _trackJson = {
  'id': 't1',
  'org_id': 'o1',
  'owner_id': 'u1',
  'name': 'Morning walk',
  'geom': {
    'type': 'LineString',
    'coordinates': [
      [7.6, 45.9],
      [7.7, 46.0],
    ],
  },
  'created_at': '2026-08-22T10:00:00Z',
};

void main() {
  group('list', () {
    test('requests an explicit higher limit and returns parsed tracks on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/tracks');
          expect(request.url.queryParameters['limit'], '200');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({'items': [_trackJson], 'limit': 200, 'offset': 0}),
            200,
          );
        }),
      );
      final repo = HttpTracksRepository(client);

      final tracks = await repo.list('tok-1');

      expect(tracks, hasLength(1));
      expect(tracks.first.id, 't1');
    });

    test('throws TrackException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 500)),
      );
      final repo = HttpTracksRepository(client);

      await expectLater(repo.list('tok-1'), throwsA(isA<TrackException>()));
    });
  });

  group('create', () {
    test('sends name and [lng, lat] coordinates and returns the created track on 201', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/tracks');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_trackJson), 201);
        }),
      );
      final repo = HttpTracksRepository(client);

      final track = await repo.create(
        'tok-1',
        name: 'Morning walk',
        points: const [TrackPoint(lat: 45.9, lng: 7.6), TrackPoint(lat: 46.0, lng: 7.7)],
      );

      expect(track.id, 't1');
      expect(capturedBody, {
        'name': 'Morning walk',
        'geom': {
          'type': 'LineString',
          'coordinates': [
            [7.6, 45.9],
            [7.7, 46.0],
          ],
        },
      });
    });

    test('throws TrackException on non-201', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 422)),
      );
      final repo = HttpTracksRepository(client);

      await expectLater(
        repo.create('tok-1', name: 'x', points: const [TrackPoint(lat: 0, lng: 0), TrackPoint(lat: 1, lng: 1)]),
        throwsA(isA<TrackException>()),
      );
    });
  });
}
