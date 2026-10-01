import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Certificates of our own servers, built into the app (`app/certs/`).
///
/// The test stand runs on a self-signed certificate and the release server on
/// one from an internal CA; Android's system store knows neither. MapLibre
/// (tiles, styles) trusts them through the generated network security config
/// (see android/app/build.gradle.kts), and Dart's HTTP stack (API, map
/// catalog, region downloads) through [installTrustedCertificates]: Dart does
/// not read the certificates a user installs on the phone.
const String certsAssetDir = 'certs/';

bool isCertificateAsset(String key) =>
    key.startsWith(certsAssetDir) && (key.endsWith('.pem') || key.endsWith('.crt'));

/// Makes every `HttpClient` the app creates (and so `package:http`) trust the
/// system roots plus the certificates in `certs/`. Does nothing when no
/// certificate is built in. Returns the assets that were installed.
Future<List<String>> installTrustedCertificates([AssetBundle? bundle]) async {
  bundle ??= rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final keys = manifest.listAssets().where(isCertificateAsset).toList()..sort();
  if (keys.isEmpty) return const [];

  final pems = <String, Uint8List>{
    for (final key in keys) key: (await bundle.load(key)).buffer.asUint8List(),
  };
  final (context, installed) = trustedContext(pems);
  if (installed.isNotEmpty) HttpOverrides.global = TrustedCertificatesOverrides(context);
  return installed;
}

/// System roots plus each PEM that parses. A broken file is skipped (and
/// logged) instead of keeping the app from starting.
(SecurityContext, List<String>) trustedContext(Map<String, Uint8List> pems) {
  final context = SecurityContext(withTrustedRoots: true);
  final installed = <String>[];
  pems.forEach((name, bytes) {
    try {
      context.setTrustedCertificatesBytes(bytes);
      installed.add(name);
    } on TlsException catch (e) {
      debugPrint('Сертификат $name пропущен: $e');
    }
  });
  return (context, installed);
}

class TrustedCertificatesOverrides extends HttpOverrides {
  TrustedCertificatesOverrides(this.context);

  final SecurityContext context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? this.context);
}
