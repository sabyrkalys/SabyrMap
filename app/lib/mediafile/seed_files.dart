import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('sabyrmap/seed');

/// Copies the map symbols and orthophotos shipped in the APK into the
/// mediafile folder (SeedFiles.kt). Runs before the app first reads that
/// folder; after an install or update only the first launch copies, and
/// files already there are kept. Never stops the app from starting.
Future<void> installSeedFiles() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<int>('install');
  } on PlatformException catch (e) {
    debugPrint('Seed files not installed: ${e.message}');
  } on MissingPluginException {
    // Tests and platforms without the native side.
  }
}
