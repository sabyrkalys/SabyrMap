import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/net/trusted_certificates.dart';

// fixtures/localhost.{crt,key}: a self-signed certificate for localhost, made
// like infra/tls/make-dev-cert.sh does for the stand. Test-only key.
final _dir = 'test/net/fixtures';
Uint8List _bytes(String name) => File('$_dir/$name').readAsBytesSync();

/// Asset bundle with the given files and a matching AssetManifest.bin.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, Uint8List> files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final name in files.keys)
          name: [
            {'asset': name},
          ],
      })!;
    }
    final data = files[key];
    if (data == null) throw FlutterError('нет $key');
    return ByteData.sublistView(data);
  }
}

void main() {
  late HttpServer server;
  late Uri url;

  setUpAll(() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(_bytes('localhost.crt'))
      ..usePrivateKeyBytes(_bytes('localhost.key'));
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server.listen((request) => request.response
      ..write('ok')
      ..close());
    url = Uri.parse('https://localhost:${server.port}/api/health');
  });

  tearDownAll(() => server.close(force: true));
  tearDown(() => HttpOverrides.global = null);

  test('only PEM files under certs/ count', () {
    expect(isCertificateAsset('certs/stand.crt'), isTrue);
    expect(isCertificateAsset('certs/internal-ca.pem'), isTrue);
    expect(isCertificateAsset('certs/README.md'), isFalse);
    expect(isCertificateAsset('assets/maps/stand.crt'), isFalse);
  });

  test('without the certificate the stand is refused', () async {
    await expectLater(http.get(url), throwsA(isA<HandshakeException>()));
  });

  test('with the certificate package:http reaches the stand', () async {
    final installed = await installTrustedCertificates(
      _Bundle({'certs/stand.crt': _bytes('localhost.crt'), 'certs/README.md': Uint8List(0)}),
    );

    expect(installed, ['certs/stand.crt']);
    final response = await http.get(url);
    expect(response.body, 'ok');
  });

  test('a broken file is skipped, the good one still works', () async {
    final installed = await installTrustedCertificates(_Bundle({
      'certs/a-broken.pem': Uint8List.fromList('not a certificate'.codeUnits),
      'certs/stand.crt': _bytes('localhost.crt'),
    }));

    expect(installed, ['certs/stand.crt']);
    expect((await http.get(url)).body, 'ok');
  });

  test('no certificates — HTTP is left as it was', () async {
    final installed = await installTrustedCertificates(_Bundle({'certs/README.md': Uint8List(0)}));

    expect(installed, isEmpty);
    expect(HttpOverrides.current, isNull);
  });
}
