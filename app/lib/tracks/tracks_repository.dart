import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'track_models.dart';

abstract class TracksRepository {
  Future<List<Track>> list(String token);

  Future<Track> create(String token, {required String name, required List<TrackPoint> points});
}

class HttpTracksRepository implements TracksRepository {
  HttpTracksRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Track>> list(String token) async {
    final response = await _client.get('/tracks?limit=200', token: token);
    if (response.statusCode != 200) {
      throw const TrackException('Could not load tracks');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Track> create(String token, {required String name, required List<TrackPoint> points}) async {
    final response = await _client.post(
      '/tracks',
      token: token,
      body: {
        'name': name,
        'geom': {
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lng, p.lat],
          ],
        },
      },
    );
    if (response.statusCode != 201) {
      throw const TrackException('Could not create track');
    }
    return Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
