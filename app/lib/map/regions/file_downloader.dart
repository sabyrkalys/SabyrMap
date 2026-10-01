import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;

import 'regions_api.dart';

/// Stops a download between chunks.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Downloads [url] into [target] with resume and an integrity check.
///
/// Bytes go to `<target>.part`; a later call continues from its length with
/// an HTTP Range request (a server that ignores Range sends the whole file
/// again, which simply restarts it). The file only gets its real name once
/// its sha256 matches — a bad file is deleted, so the next try starts clean.
Future<void> downloadFile({
  required http.Client client,
  required Uri url,
  required File target,
  required int expectedSize,
  required String sha256Hex,
  void Function(int receivedBytes)? onProgress,
  CancelToken? cancel,
}) async {
  if (target.existsSync() && target.lengthSync() == expectedSize && await _sha256(target) == sha256Hex) {
    onProgress?.call(expectedSize);
    return;
  }
  final part = target.fileSystem.file('${target.path}.part');
  var have = part.existsSync() ? part.lengthSync() : 0;
  if (have > expectedSize) {
    part.deleteSync();
    have = 0;
  }
  if (have < expectedSize) {
    final request = http.Request('GET', url);
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (_) {
      throw const RegionException('Нет связи с сервером карт');
    }
    final FileMode mode;
    if (response.statusCode == 206 && have > 0) {
      mode = FileMode.append;
    } else if (response.statusCode == 200) {
      have = 0;
      mode = FileMode.write;
    } else {
      await response.stream.drain<void>();
      throw RegionException('Не удалось скачать ${target.basename} (HTTP ${response.statusCode})');
    }
    final sink = part.openWrite(mode: mode);
    try {
      await for (final chunk in response.stream) {
        if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        have += chunk.length;
        onProgress?.call(have);
      }
    } catch (e) {
      if (e is DownloadCancelled) rethrow;
      throw const RegionException('Связь прервалась — скачивание продолжится с того же места');
    } finally {
      await sink.close();
    }
  }
  if (await _sha256(part) != sha256Hex) {
    part.deleteSync();
    throw RegionException('Файл ${target.basename} повреждён при скачивании — попробуйте ещё раз');
  }
  if (target.existsSync()) target.deleteSync();
  part.renameSync(target.path);
}

Future<String> _sha256(File file) async => (await sha256.bind(file.openRead()).first).toString();
