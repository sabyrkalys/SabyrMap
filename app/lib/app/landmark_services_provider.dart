import 'package:app/config/storage_paths.dart' as mock;
import 'package:app/landmarks/on_screen/on_screen_registry.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Сервисы локальных меток, карт и навигации. `main` собирает их через
/// [LandmarkServices.bootstrap] и подставляет сюда; без этого чтение —
/// [StateError] (тесты подставляют свои подделки на уровне выше).
final landmarkServicesProvider = Provider<LandmarkServices>(
  (ref) => throw StateError('LandmarkServices are not bootstrapped; override landmarkServicesProvider'),
);

/// Папки групп диалога «Путевая точка».
class MarkerGroupFolders {
  const MarkerGroupFolders({required this.unsorted, required this.myMarkers, this.appRoot});

  /// «Несортированные метки» — папка меток по умолчанию.
  final String unsorted;

  /// «Мои метки» — корень папки меток.
  final String myMarkers;

  /// Корень данных приложения; пути показываются относительно него.
  final String? appRoot;

  /// Путь [folder] для показа: относительно [appRoot], если он внутри.
  /// Decision: полный путь на Android содержит идентификатор пакета
  /// приложения — пользователю он не нужен.
  String display(String folder) {
    final root = appRoot;
    return root != null && p.isWithin(root, folder) ? p.relative(folder, from: root) : folder;
  }
}

/// Decision: по умолчанию — прежние пути-заглушки, чтобы диалог работал и
/// без сервисов (в тестах); `main` подставляет настоящие папки.
final markerGroupFoldersProvider = Provider<MarkerGroupFolders>(
  (ref) => MarkerGroupFolders(unsorted: mock.StoragePaths.unsorted, myMarkers: mock.StoragePaths.landmarks),
);

/// Открывает «Локальные метки» поверх [BuildContext]. Задаётся в `main`;
/// по умолчанию ничего не делает (тесты подставляют свою запись вызова).
final allMarkersOpenerProvider = Provider<void Function(BuildContext context)>((ref) => (_) {});

/// «Метки на экране»: что из меток видно на карте. `main` подставляет
/// реестр из [LandmarkServices]; по умолчанию (тесты) — пустой, всё видно.
final onScreenRegistryProvider = Provider<OnScreenRegistry>((ref) => OnScreenRegistry());
