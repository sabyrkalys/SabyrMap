import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' show LatLngBounds;

/// A problem with an offline region, worded for the user.
class RegionException implements Exception {
  const RegionException(this.message);

  final String message;

  @override
  String toString() => 'RegionException: $message';
}

/// [west, south, east, north], as the server takes it.
List<double> bboxOf(LatLngBounds bounds) => [
      bounds.southwest.longitude,
      bounds.southwest.latitude,
      bounds.northeast.longitude,
      bounds.northeast.latitude,
    ];

class RegionEstimate {
  const RegionEstimate({required this.totalBytes, required this.maxBytes, required this.allowed});

  final int totalBytes;
  final int maxBytes;

  /// Within the server's size limit.
  final bool allowed;

  factory RegionEstimate.fromJson(Map<String, dynamic> json) => RegionEstimate(
        totalBytes: (json['total_bytes'] as num).toInt(),
        maxBytes: (json['max_bytes'] as num).toInt(),
        allowed: json['allowed'] as bool,
      );
}

class RegionFile {
  const RegionFile({required this.name, required this.size, required this.sha256});

  final String name;
  final int size;
  final String sha256;

  factory RegionFile.fromJson(Map<String, dynamic> json) => RegionFile(
        name: json['name'] as String,
        size: (json['size'] as num).toInt(),
        sha256: json['sha256'] as String,
      );
}

enum RegionJobStatus { queued, running, ready, failed, expired }

/// A region on the server (POST /regions, GET /regions/{id}).
class RegionJob {
  const RegionJob({
    required this.id,
    required this.mapId,
    required this.status,
    required this.progress,
    required this.files,
    this.error,
  });

  final String id;
  final String mapId;
  final RegionJobStatus status;

  /// Cutting progress on the server, 0–1.
  final double progress;
  final List<RegionFile> files;
  final String? error;

  factory RegionJob.fromJson(Map<String, dynamic> json) => RegionJob(
        id: json['id'] as String,
        mapId: json['map_id'] as String,
        status: RegionJobStatus.values.byName(json['status'] as String),
        progress: (json['progress'] as num).toDouble(),
        files: [for (final f in json['files'] as List<dynamic>) RegionFile.fromJson(f as Map<String, dynamic>)],
        error: json['error'] as String?,
      );
}

/// Our server's /regions endpoints. No login: the server runs in
/// single-user mode, the network keeps strangers out.
class RegionsApi {
  RegionsApi({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  http.Client get httpClient => _http;

  static const _json = {'Content-Type': 'application/json'};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Uri downloadUri(String jobId, String fileName) =>
      _uri('/regions/$jobId/download/${Uri.encodeComponent(fileName)}');

  Future<RegionEstimate> estimate({required String mapId, required LatLngBounds bounds, required int maxZoom}) async {
    final body = await _send(() => _http.post(_uri('/regions/estimate'),
        headers: _json, body: jsonEncode({'map_id': mapId, 'bbox': bboxOf(bounds), 'max_zoom': maxZoom})));
    return RegionEstimate.fromJson(body);
  }

  /// Queues the region, or returns an equal one the server already has.
  Future<RegionJob> create({
    required String mapId,
    required List<double> bbox,
    required int maxZoom,
    String? name,
  }) async {
    final body = await _send(() => _http.post(_uri('/regions'),
        headers: _json,
        body: jsonEncode({'map_id': mapId, 'bbox': bbox, 'max_zoom': maxZoom, if (name != null) 'name': name})));
    return RegionJob.fromJson(body);
  }

  Future<RegionJob> get(String id) async => RegionJob.fromJson(await _send(() => _http.get(_uri('/regions/$id'))));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } catch (_) {
      throw const RegionException('Нет связи с сервером карт');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw RegionException('Сервер карт ответил ошибкой (HTTP ${response.statusCode})');
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    throw RegionException(detail is String ? detail : 'Сервер карт ответил ошибкой (HTTP ${response.statusCode})');
  }
}
