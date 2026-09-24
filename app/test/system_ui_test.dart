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

  test('navigation bar style is fully transparent with icons contrasting the theme', () {
    final light = systemNavigationBarStyle(Brightness.light);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.systemNavigationBarDividerColor, Colors.transparent);
    expect(light.systemNavigationBarContrastEnforced, isFalse);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);

    expect(systemNavigationBarStyle(Brightness.dark).systemNavigationBarIconBrightness, Brightness.light);
  });
}
