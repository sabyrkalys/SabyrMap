import 'dart:convert';

import 'package:app/map/regions/file_downloader.dart';
import 'package:app/map/regions/regions_api.dart';
import 'package:crypto/crypto.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final data = utf8.encode('0123456789' * 100);
  final hash = sha256.convert(data).toString();
  final url = Uri.parse('http://api.test/regions/1/download/sat.mbtiles');
  late MemoryFileSystem fs;
  late List<String?> ranges;

  setUp(() {
    fs = MemoryFileSystem();
    fs.directory('/maps').createSync();
    ranges = [];
  });

  /// A server that honours Range like nginx does.
  MockClient server({bool ignoreRange = false, List<int>? body}) => MockClient((request) async {
        final payload = body ?? data;
        final range = request.headers['Range'];
        ranges.add(range);
        if (range != null && !ignoreRange) {
          final from = int.parse(range.substring('bytes='.length, range.length - 1));
          return http.Response.bytes(payload.sublist(from), 206);
        }
        return http.Response.bytes(payload, 200);
      });

  Future<void> download(http.Client client, {void Function(int)? onProgress, CancelToken? cancel}) => downloadFile(
        client: client,
        url: url,
        target: fs.file('/maps/sat.mbtiles'),
        expectedSize: data.length,
        sha256Hex: hash,
        onProgress: onProgress,
        cancel: cancel,
      );

  test('downloads a file and checks its sha256', () async {
    final progress = <int>[];
    await download(server(), onProgress: progress.add);

    expect(fs.file('/maps/sat.mbtiles').readAsBytesSync(), data);
    expect(fs.file('/maps/sat.mbtiles.part').existsSync(), isFalse);
    expect(ranges, [null]);
    expect(progress.last, data.length);
  });

  test('continues a partial download with a Range request', () async {
    fs.file('/maps/sat.mbtiles.part').writeAsBytesSync(data.sublist(0, 400));

    await download(server());

    expect(ranges, ['bytes=400-']);
    expect(fs.file('/maps/sat.mbtiles').readAsBytesSync(), data);
  });

  test('a server that ignores Range sends everything again and that still works', () async {
    fs.file('/maps/sat.mbtiles.part').writeAsBytesSync(data.sublist(0, 400));

    await download(server(ignoreRange: true));

    expect(fs.file('/maps/sat.mbtiles').readAsBytesSync(), data);
  });

  test('a corrupted file is rejected and removed so the next try starts clean', () async {
    final broken = List.of(data)..[10] = 0;

    await expectLater(download(server(body: broken)), throwsA(isA<RegionException>()));

    expect(fs.file('/maps/sat.mbtiles').existsSync(), isFalse);
    expect(fs.file('/maps/sat.mbtiles.part').existsSync(), isFalse);
  });

  test('a file that is already complete is not downloaded again', () async {
    fs.file('/maps/sat.mbtiles').writeAsBytesSync(data);

    await download(server());

    expect(ranges, isEmpty);
  });

  test('HTTP errors and lost connections are user messages', () async {
    await expectLater(
      download(MockClient((_) async => http.Response('', 404))),
      throwsA(isA<RegionException>().having((e) => e.message, 'message', contains('HTTP 404'))),
    );
    await expectLater(
      download(MockClient((_) async => throw http.ClientException('offline'))),
      throwsA(isA<RegionException>().having((e) => e.message, 'message', 'Нет связи с сервером карт')),
    );
  });

  test('cancel stops the download and keeps the part for later', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(download(server(), cancel: cancel), throwsA(isA<DownloadCancelled>()));
    expect(fs.file('/maps/sat.mbtiles').existsSync(), isFalse);
  });
}
