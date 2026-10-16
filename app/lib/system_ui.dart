import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hides both Android system bars app-wide: the status bar and the three
/// navigation buttons. A swipe from the screen edge shows them for a moment
/// over the app, and Android hides them again by itself (sticky immersive
/// mode). Flutter re-applies the mode when the app returns from the
/// background.
Future<void> configureSystemUi() {
  return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
