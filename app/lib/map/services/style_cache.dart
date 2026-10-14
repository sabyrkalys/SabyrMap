import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Стили векторных слоёв (например, дороги без спутника), сохранённые на
/// телефоне: свежий берётся с сервера и сохраняется, а без связи — последний
/// сохранённый. Тайлы MapLibre берёт из своего кэша.
class StyleCache {
  StyleCache({
    required this.directory,
    Future<String> Function(Uri url)? network,
    this.timeout = const Duration(seconds: 10),
  }) : _network = network ?? _httpText;

  final Future<Directory> Function() directory;
  final Future<String> Function(Uri url) _network;
  final Duration timeout;

  static Future<String> _httpText(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: url);
    return utf8.decode(response.bodyBytes);
  }

  Future<File> _fileOf(Uri url) async =>
      File('${(await directory()).path}/${sha1.convert(utf8.encode('$url')).toString().substring(0, 16)}.json');

  /// Стиль [url]: с сервера (и сохранить), иначе сохранённый; нет и его —
  /// ошибка сервера.
  Future<String> fetch(Uri url) async {
    try {
      final text = await _network(url).timeout(timeout);
      jsonDecode(text); // не сохранять страницу ошибки
      try {
        final file = await _fileOf(url);
        await file.parent.create(recursive: true);
        await file.writeAsString(text, flush: true);
      } on Object {
        // Не сохранилось — карта всё равно получит стиль.
      }
      return text;
    } on Object {
      final file = await _fileOf(url);
      if (file.existsSync()) return file.readAsString();
      rethrow;
    }
  }
}

final styleCacheProvider = Provider<StyleCache>((ref) => StyleCache(
      directory: () async => Directory('${(await getApplicationSupportDirectory()).path}/styles'),
    ));
