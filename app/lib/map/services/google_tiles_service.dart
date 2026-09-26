import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../models/map_models.dart';

class GoogleTilesException implements Exception {
  const GoogleTilesException(this.message, {this.detail});

  /// Shown to the user.
  final String message;

  /// For logs: status code, server text or the underlying error.
  final String? detail;

  @override
  String toString() => 'GoogleTilesException: $message${detail == null ? '' : ' ($detail)'}';
}

class _Session {
  const _Session(this.token, this.expiry);

  final String token;
  final DateTime expiry;
}

/// Google Map Tiles API (2D tiles): creates and caches session tokens and
/// builds tile URLs for MapLibre.
///
/// A session is tied to its map type, so one is kept per map type (and
/// layer types) for the app's lifetime; it is renewed a day before it
/// expires, or after [invalidate] (e.g. a 401/403 on tiles).
class GoogleTilesService {
  GoogleTilesService({
    required String apiKey,
    http.Client? httpClient,
    DateTime Function()? clock,
    this.language = 'ru-RU',
    this.region = 'RU',
    this.timeout = const Duration(seconds: 15),
  }) : _apiKey = apiKey,
       _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  static const String userMessage = 'Google-слой недоступен, проверьте подключение';
  static const Duration renewBefore = Duration(days: 1);

  final String _apiKey;
  final http.Client _http;
  final DateTime Function() _clock;
  final String language;
  final String region;
  final Duration timeout;

  final Map<String, _Session> _sessions = {};
  final Map<String, Future<String>> _pending = {};

  static String _cacheKey(String mapType, List<String> layerTypes) => '$mapType|${layerTypes.join(',')}';

  static (String, List<String>) _typesOf(MapSource source) {
    final mapType = source.extraParams?['mapType'];
    if (mapType == null || mapType.isEmpty) {
      throw ArgumentError.value(source.id, 'source', 'not a Google source: no mapType');
    }
    final layers = source.extraParams?['layerTypes'];
    return (mapType, layers == null || layers.isEmpty ? const [] : layers.split(','));
  }

  /// A valid session token for [source]'s map type.
  Future<String> sessionFor(MapSource source) {
    final (mapType, layerTypes) = _typesOf(source);
    final key = _cacheKey(mapType, layerTypes);
    final cached = _sessions[key];
    if (cached != null && _clock().isBefore(cached.expiry.subtract(renewBefore))) {
      return Future.value(cached.token);
    }
    // The callback must not return the removed future: whenComplete would
    // then wait for the very future it is completing, and never finish.
    return _pending[key] ??= _create(key, mapType, layerTypes).whenComplete(() {
      _pending.remove(key);
    });
  }

  /// Forgets [source]'s session so the next [sessionFor] creates a new one.
  void invalidate(MapSource source) {
    final (mapType, layerTypes) = _typesOf(source);
    _sessions.remove(_cacheKey(mapType, layerTypes));
  }

  /// `{z}/{x}/{y}` template for MapLibre's raster source.
  Future<String> tileUrlTemplate(MapSource source) async {
    final session = await sessionFor(source);
    return 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}'
        '?session=${Uri.encodeQueryComponent(session)}&key=${Uri.encodeQueryComponent(_apiKey)}';
  }

  final Set<String> _verified = {};

  /// Fetches the zoom-0 tile once per source to catch a rejected key or
  /// session before the layer is shown (MapLibre doesn't report per-tile
  /// HTTP errors). A 401/403 gets one retry with a fresh session.
  Future<void> verifyAccess(MapSource source) async {
    if (_verified.contains(source.id)) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      final url = Uri.parse(
        (await tileUrlTemplate(source)).replaceAll('{z}', '0').replaceAll('{x}', '0').replaceAll('{y}', '0'),
      );
      final http.Response response;
      try {
        response = await _http.get(url).timeout(timeout);
      } on TimeoutException {
        throw const GoogleTilesException(userMessage, detail: 'tile request timed out');
      } catch (e) {
        throw GoogleTilesException(userMessage, detail: '$e');
      }
      if (response.statusCode == 200) {
        _verified.add(source.id);
        return;
      }
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw GoogleTilesException(userMessage, detail: 'tile HTTP ${response.statusCode}');
      }
      invalidate(source);
    }
    throw const GoogleTilesException(userMessage, detail: 'tile rejected after a fresh session');
  }

  Future<String> _create(String key, String mapType, List<String> layerTypes) async {
    if (_apiKey.isEmpty) {
      throw const GoogleTilesException('Не задан ключ Google Maps (googleMapsApiKey в config.dart)');
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('https://tile.googleapis.com/v1/createSession?key=${Uri.encodeQueryComponent(_apiKey)}'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mapType': mapType,
              'language': language,
              'region': region,
              if (layerTypes.isNotEmpty) 'layerTypes': layerTypes,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const GoogleTilesException(userMessage, detail: 'createSession timed out');
    } catch (e) {
      throw GoogleTilesException(userMessage, detail: '$e');
    }
    if (response.statusCode != 200) {
      throw GoogleTilesException(userMessage, detail: 'HTTP ${response.statusCode}: ${response.body}');
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final token = json['session'] as String;
      final expirySeconds = int.parse(json['expiry'] as String);
      final session = _Session(token, DateTime.fromMillisecondsSinceEpoch(expirySeconds * 1000, isUtc: true));
      _sessions[key] = session;
      return token;
    } catch (e) {
      throw GoogleTilesException(userMessage, detail: 'bad createSession response: $e');
    }
  }
}

final googleTilesServiceProvider = Provider<GoogleTilesService>(
  (ref) => GoogleTilesService(apiKey: AppConfig.googleMapsApiKey),
);
