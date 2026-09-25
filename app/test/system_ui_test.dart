import 'package:app/system_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configureSystemUi hides the status bar and keeps the navigation bar', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await configureSystemUi();

    final overlaysCall = calls.singleWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays');
    expect(overlaysCall.arguments, ['SystemUiOverlay.bottom']);
  });

  testWidgets('status bar revealed by a swipe is hidden again after a short delay', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      SystemChrome.setSystemUIChangeCallback(null);
    });

    await configureSystemUi();
    calls.clear();

    // Not awaited: the reply only arrives once the re-hide delay has elapsed.
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.platform.name,
      SystemChannels.platform.codec.encodeMethodCall(const MethodCall('SystemChrome.systemUIChange', [true])),
      (_) {},
    );
    await tester.pump(systemBarsRehideDelay - const Duration(milliseconds: 1));
    expect(calls.where((c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays'), isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    final overlaysCall = calls.singleWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays');
    expect(overlaysCall.arguments, ['SystemUiOverlay.bottom']);
  });

  test('navigation bar style is fully transparent with icons contrasting the theme', () {
    final light = systemNavigationBarStyle(Brightness.light);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.systemNavigationBarDividerColor, Colors.transparent);
    expect(light.systemNavigationBarContrastEnforced, isFalse);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);

    expect(systemNavigationBarStyle(Brightness.dark).systemNavigationBarIconBrightness, Brightness.light);
  });
}
