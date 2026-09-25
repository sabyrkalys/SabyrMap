import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long a status bar revealed by a swipe stays before it is hidden again.
const systemBarsRehideDelay = Duration(seconds: 3);

/// Hides the Android status bar app-wide and keeps the system navigation bar.
/// In manual mode Android leaves the status bar up after a swipe from the
/// top, so it is hidden again after [systemBarsRehideDelay]. Flutter
/// re-applies this mode when the app returns from the background.
Future<void> configureSystemUi() async {
  await _hideStatusBar();
  await SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
    if (!systemOverlaysAreVisible) return;
    await Future<void>.delayed(systemBarsRehideDelay);
    await _hideStatusBar();
  });
}

Future<void> _hideStatusBar() {
  return SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
}

/// Fully transparent system navigation bar so the map shows beneath it;
/// its icons contrast the app theme. [systemNavigationBarContrastEnforced]
/// is off, otherwise Android adds its own scrim behind the gesture handle.
SystemUiOverlayStyle systemNavigationBarStyle(Brightness themeBrightness) {
  return SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: themeBrightness == Brightness.light ? Brightness.dark : Brightness.light,
  );
}
