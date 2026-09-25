import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home/home_shell.dart';
import 'licenses.dart';
import 'system_ui.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSystemUi();
  registerThirdPartyLicenses();
  runApp(const ProviderScope(child: AlpineQuestApp()));
}

class AlpineQuestApp extends StatelessWidget {
  const AlpineQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlpineQuest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Always light, independent of the Android system theme; the dark
      // theme is kept for a future in-app night mode.
      themeMode: ThemeMode.light,
      home: const HomeShell(),
    );
  }
}
