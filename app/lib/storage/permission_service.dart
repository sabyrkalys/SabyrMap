import 'storage_service.dart';

/// Доступ приложения к папкам вне своей (загрузки, общая память).
/// Системный запрос разрешения — платформенный слой.
abstract class PermissionService {
  const PermissionService();

  /// Можно ли писать в [path].
  Future<bool> hasAccess(String path);

  /// Попросить доступ у системы; true — выдан.
  Future<bool> request();

  /// null — доступ есть; иначе сообщение для пользователя.
  Future<String?> ensureAccess(String path);
}

/// Проверка доступа пробной записью; запросить разрешение у системы этот
/// вариант не умеет — [request] честно отвечает false.
class WriteCheckPermissionService extends PermissionService {
  const WriteCheckPermissionService(this._storage);

  final StorageService _storage;

  @override
  Future<bool> hasAccess(String path) async => (await _storage.checkWriteAccess(path)).granted;

  @override
  Future<bool> request() async => false;

  @override
  Future<String?> ensureAccess(String path) async {
    final access = await _storage.checkWriteAccess(path);
    return access.granted ? null : 'Нет доступа к папке: ${access.reason ?? path}';
  }
}
