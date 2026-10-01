import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home/home_shell.dart';
import 'licenses.dart';
import 'net/trusted_certificates.dart';
import 'system_ui.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSystemUi();
  await installTrustedCertificates();
  registerThirdPartyLicenses();
  runApp(const ProviderScope(child: SabyrMapApp()));
}

class SabyrMapApp extends StatelessWidget {
  const SabyrMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabyrMap',
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
