import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../models/map_models.dart';

class YandexTilesException implements Exception {
  const YandexTilesException(this.message, {this.detail});

  /// Shown to the user.
  final String message;

  /// For logs.
  final String? detail;

  @override
  String toString() => 'YandexTilesException: $message${detail == null ? '' : ' ($detail)'}';
}

/// Яндекс Tiles API: the key is static and goes into every tile URL.
///
/// MapLibre loads tiles natively and doesn't report per-tile HTTP errors, so
/// a rejected key (403) is caught up front by [verifyAccess], which fetches
/// one zoom-0 tile before the layer is added.
class YandexTilesService {
  YandexTilesService({required String apiKey, http.Client? httpClient, this.timeout = const Duration(seconds: 15)})
      : _apiKey = apiKey,
        _http = httpClient ?? http.Client();

  static const String forbiddenMessage = 'Яндекс-слой недоступен: ключ не принят';
  static const String unavailableMessage = 'Яндекс-слой недоступен, проверьте подключение';

  final String _apiKey;
  final http.Client _http;
  final Duration timeout;

  final Set<String> _verified = {};

  void _requireKey() {
    if (_apiKey.isEmpty) {
      throw const YandexTilesException('Не задан ключ Яндекс Карт (yandexMapsApiKey в config.dart)');
    }
  }

  /// The source's `{x}/{y}/{z}` template with the key appended.
  String tileUrlTemplate(MapSource source) {
    final template = source.tileUrlTemplate;
    if (template == null || template.isEmpty) {
      throw ArgumentError.value(source.id, 'source', 'not a Яндекс source: no tileUrlTemplate');
    }
    _requireKey();
    return '$template&apikey=${Uri.encodeQueryComponent(_apiKey)}';
  }

  /// Fetches the zoom-0 tile once per source; throws [YandexTilesException]
  /// when the key is rejected or the service can't be reached.
  Future<void> verifyAccess(MapSource source) async {
    final template = tileUrlTemplate(source);
    if (_verified.contains(source.id)) return;
    final url = Uri.parse(template.replaceAll('{x}', '0').replaceAll('{y}', '0').replaceAll('{z}', '0'));
    final http.Response response;
    try {
      response = await _http.get(url).timeout(timeout);
    } on TimeoutException {
      throw const YandexTilesException(unavailableMessage, detail: 'tile request timed out');
    } catch (e) {
      throw YandexTilesException(unavailableMessage, detail: '$e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw YandexTilesException(forbiddenMessage, detail: 'HTTP ${response.statusCode}');
    }
    if (response.statusCode != 200) {
      throw YandexTilesException(unavailableMessage, detail: 'HTTP ${response.statusCode}');
    }
    _verified.add(source.id);
  }
}

final yandexTilesServiceProvider = Provider<YandexTilesService>(
  (ref) => YandexTilesService(apiKey: AppConfig.yandexMapsApiKey),
);
