import 'share_target.dart';

/// Отправка файлов и текста в другие приложения. Реализация —
/// платформенный слой.
abstract class ShareService {
  const ShareService();

  Future<void> shareFile(String path, {ShareTarget target = ShareTarget.system, String? mimeType, String? message});

  Future<void> shareText(String text, {ShareTarget target = ShareTarget.system});
}

/// Платформенная отправка ещё не подключена: вызов сообщает об этом
/// [UnsupportedError], а не молча ничего не делает.
class UnavailableShareService extends ShareService {
  const UnavailableShareService();

  @override
  Future<void> shareFile(String path, {ShareTarget target = ShareTarget.system, String? mimeType, String? message}) =>
      Future.error(UnsupportedError('Sharing is not connected on this platform'));

  @override
  Future<void> shareText(String text, {ShareTarget target = ShareTarget.system}) =>
      Future.error(UnsupportedError('Sharing is not connected on this platform'));
}
