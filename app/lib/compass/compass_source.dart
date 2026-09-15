import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstraction over the device's compass sensor, so widgets don't call the
/// static [FlutterCompass] API directly and can be tested with a fake heading
/// stream instead of a real (or, in a test environment, absent) platform
/// channel.
abstract class CompassSource {
  /// A stream of headings in degrees (0-360, 0 = north), or null if no
  /// compass sensor is available on this device/platform.
  Stream<double?>? get headingStream;
}

class DeviceCompassSource implements CompassSource {
  @override
  Stream<double?>? get headingStream => FlutterCompass.events?.map((event) => event.heading);
}

final compassSourceProvider = Provider<CompassSource>((ref) => DeviceCompassSource());
