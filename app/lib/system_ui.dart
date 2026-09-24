import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hides the Android status bar app-wide (a swipe from the top still reveals
/// it transiently) and keeps the system navigation bar. Flutter re-applies
/// this mode when the app returns from the background.
Future<void> configureSystemUi() {
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
