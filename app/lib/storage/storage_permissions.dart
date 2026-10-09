import 'storage_paths.dart';
import 'storage_service.dart';

/// Права на запись в хранилище sabyrmap.
///
/// Decision: корень — собственная папка приложения
/// (`/Android/data/<pkg>/files` или внутренняя), для неё Android не требует
/// runtime-разрешений, поэтому «права» здесь — это фактическая проверка
/// записи, а не системный диалог. Папки вне корня (выбор пользователя при
/// импорте/экспорте) — следующие спринты.
class StoragePermissions {
  const StoragePermissions(this._service, this._paths);

  final StorageService _service;
  final StoragePaths _paths;

  /// Нужен ли системный запрос разрешения для корня приложения.
  bool get requiresRuntimePermission => false;

  /// Создаёт базовые папки и проверяет, что в корень и в папку меток можно
  /// писать. Возвращает первый отказ или разрешение.
  Future<WriteAccess> verify() async {
    await _service.ensureBaseFolders();
    for (final dir in [_paths.appRoot, _paths.landmarks]) {
      final access = await _service.checkWriteAccess(dir);
      if (!access.granted) return access;
    }
    return const WriteAccess(granted: true);
  }
}
