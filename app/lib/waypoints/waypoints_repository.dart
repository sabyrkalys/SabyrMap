import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'waypoint_models.dart';

abstract class WaypointsRepository {
  Future<List<Waypoint>> list(String token);

  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  });

  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  });

  Future<void> delete(String token, String id);
}

class HttpWaypointsRepository implements WaypointsRepository {
  HttpWaypointsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Waypoint>> list(String token) async {
    final response = await _client.get('/waypoints?limit=200', token: token);
    if (response.statusCode != 200) {
      throw const WaypointException('Could not load waypoints');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items.map((e) => Waypoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  }) async {
    final response = await _client.post(
      '/waypoints',
      token: token,
      body: {
        'name': name,
        'type': type,
        'note': note,
        'color': color,
        'geom': {
          'type': 'Point',
          'coordinates': [lng, lat],
        },
      },
    );
    if (response.statusCode != 201) {
      throw const WaypointException('Could not create waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  }) async {
    final response = await _client.patch(
      '/waypoints/$id',
      token: token,
      body: {'name': name, 'type': type, 'note': note, 'color': color},
    );
    if (response.statusCode != 200) {
      throw const WaypointException('Could not update waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String token, String id) async {
    final response = await _client.delete('/waypoints/$id', token: token);
    if (response.statusCode != 204) {
      throw const WaypointException('Could not delete waypoint');
    }
  }
}
