import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/landmark_services_provider.dart';
import 'explorer/local_landmarks_screen.dart';
import 'home/home_shell.dart';
import 'landmarks/services/landmark_services.dart';
import 'licenses.dart';
import 'mediafile/seed_files.dart';
import 'net/trusted_certificates.dart';
import 'system_ui.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSystemUi();
  await installTrustedCertificates();
  registerThirdPartyLicenses();
  await installSeedFiles();
  final services = await LandmarkServices.bootstrap();
  runApp(
    ProviderScope(
      overrides: [
        landmarkServicesProvider.overrideWithValue(services),
        onScreenRegistryProvider.overrideWithValue(services.onScreen),
        allMarkersOpenerProvider.overrideWithValue(
          (context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LocalLandmarksScreen())),
        ),
        markerGroupFoldersProvider.overrideWithValue(
          MarkerGroupFolders(
            unsorted: await services.folders.getDefaultFolder(),
            myMarkers: services.repository.storage.paths.landmarks,
            appRoot: services.repository.storage.paths.appRoot,
          ),
        ),
      ],
      child: const SabyrMapApp(),
    ),
  );
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
