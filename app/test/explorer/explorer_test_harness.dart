import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/explorer/explorer_providers.dart';
import 'package:app/explorer/local_landmarks_screen.dart';
import 'package:app/landmarks/explorer/places/places_provider.dart';
import 'package:app/map/regions/server_region_service.dart';
import 'package:app/storage/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

/// Объём раздела для тестов: 487 ГБ, занято 239 ГБ.
class FakeStorageInfo implements StorageInfo {
  const FakeStorageInfo();

  static const int gb = 1 << 30;

  @override
  Future<int?> totalBytes(String path) async => 487 * gb;

  @override
  Future<int?> freeBytes(String path) async => 248 * gb;
}

/// Доступ по списку папок, запрос — по флагу; записывает вызовы.
class FakePermissionService extends PermissionService {
  FakePermissionService({this.denied = const {}, this.grantOnRequest = false});

  Set<String> denied;
  bool grantOnRequest;
  int requests = 0;

  @override
  Future<bool> hasAccess(String path) async => !denied.contains(path);

  @override
  Future<bool> request() async {
    requests++;
    if (grantOnRequest) denied = {};
    return grantOnRequest;
  }

  @override
  Future<String?> ensureAccess(String path) async => denied.contains(path) ? 'denied' : null;
}

/// Сервисы во временной папке с загрузками и «памятью устройства».
class ExplorerHarness {
  ExplorerHarness._(this.f, this.downloads, this.device, this.permissions);

  final ServicesFixture f;
  final String downloads;
  final String device;
  final FakePermissionService permissions;

  static Future<ExplorerHarness> create(WidgetTester tester, {Set<String> Function(ExplorerHarness)? denied}) async {
    late ExplorerHarness h;
    await tester.runAsync(() async {
      final permissions = FakePermissionService();
      late String downloads;
      late String device;
      final f = await ServicesFixture.create(
        permissions: permissions,
        places: (paths) {
          downloads = p.join(paths.appRoot, 'Download');
          device = p.join(paths.appRoot, 'device');
          Directory(downloads).createSync(recursive: true);
          Directory(p.join(device, 'DCIM')).createSync(recursive: true);
          Directory(p.join(device, 'Music')).createSync(recursive: true);
          return PlacesProvider(paths, downloads: () async => downloads, device: () async => device);
        },
      );
      h = ExplorerHarness._(f, downloads, device, permissions);
    });
    if (denied != null) h.permissions.denied = denied(h);
    return h;
  }

  Widget app({String? initialFolder}) => ProviderScope(
    overrides: [
      landmarkServicesProvider.overrideWithValue(f.services),
      storageInfoProvider.overrideWithValue(const FakeStorageInfo()),
    ],
    child: MaterialApp(home: LocalLandmarksScreen(initialFolder: initialFolder)),
  );

  /// Даёт файловым операциям завершиться и перерисовывает экран. Всё —
  /// в настоящем времени: операции с диском, начатые в «фальшивом» времени
  /// теста, не завершаются.
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    }
    await tester.pump();
  }

  /// Показывает экран.
  Future<void> pumpApp(WidgetTester tester, {String? initialFolder}) async {
    await tester.runAsync(() => tester.pumpWidget(app(initialFolder: initialFolder)));
    await settle(tester);
  }

  /// Нажатие, обработчик которого работает с диском.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() => tester.tap(finder));
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.runAsync(() async {
      if (f.root.existsSync()) f.root.deleteSync(recursive: true);
    });
  }
}
