import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _waypointJson = {
  'id': 'w1',
  'org_id': 'o1',
  'owner_id': 'u1',
  'name': 'Trailhead',
  'type': 'generic',
  'note': null,
  'geom': {
    'type': 'Point',
    'coordinates': [7.6, 45.9],
  },
  'can_edit': true,
  'created_at': '2026-08-22T10:00:00Z',
};

void main() {
  group('list', () {
    test('returns parsed waypoints on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints');
          expect(request.url.queryParameters['limit'], '200');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({'items': [_waypointJson], 'limit': 50, 'offset': 0}),
            200,
          );
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoints = await repo.list('tok-1');

      expect(waypoints, hasLength(1));
      expect(waypoints.first.id, 'w1');
    });

    test('throws WaypointException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 500)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(repo.list('tok-1'), throwsA(isA<WaypointException>()));
    });
  });

  group('create', () {
    test('sends name/type/note/geom and returns the created waypoint on 201', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_waypointJson), 201);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoint = await repo.create(
        'tok-1',
        name: 'Trailhead',
        type: 'generic',
        note: '',
        lat: 45.9,
        lng: 7.6,
      );

      expect(waypoint.id, 'w1');
      expect(capturedBody, {
        'name': 'Trailhead',
        'type': 'generic',
        'note': '',
        'geom': {
          'type': 'Point',
          'coordinates': [7.6, 45.9],
        },
      });
    });

    test('throws WaypointException on non-201', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 422)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(
        repo.create('tok-1', name: '', type: 'generic', note: '', lat: 0, lng: 0),
        throwsA(isA<WaypointException>()),
      );
    });
  });

  group('update', () {
    test('sends name/type/note and returns the updated waypoint on 200', () async {
      Map<String, dynamic>? capturedBody;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints/w1');
          expect(request.method, 'PATCH');
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_waypointJson), 200);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      final waypoint = await repo.update('tok-1', 'w1', name: 'New name', type: 'danger', note: 'Careful');

      expect(waypoint.id, 'w1');
      expect(capturedBody, {'name': 'New name', 'type': 'danger', 'note': 'Careful'});
    });

    test('throws WaypointException on non-200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 403)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(
        repo.update('tok-1', 'w1', name: 'x', type: 'generic', note: ''),
        throwsA(isA<WaypointException>()),
      );
    });
  });

  group('delete', () {
    test('completes normally on 204', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/waypoints/w1');
          expect(request.method, 'DELETE');
          return http.Response('', 204);
        }),
      );
      final repo = HttpWaypointsRepository(client);

      await repo.delete('tok-1', 'w1');
    });

    test('throws WaypointException on non-204', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{}', 403)),
      );
      final repo = HttpWaypointsRepository(client);

      await expectLater(repo.delete('tok-1', 'w1'), throwsA(isA<WaypointException>()));
    });
  });
}
