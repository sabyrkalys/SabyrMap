import 'package:app/system_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configureSystemUi hides both system bars until a swipe from the edge (sticky immersive)', () async {
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

    final modeCall = calls.singleWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIMode');
    expect(modeCall.arguments, 'SystemUiMode.immersiveSticky');
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
